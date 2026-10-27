import 'dart:convert';

import 'package:http/http.dart' as http;

import 'domain.dart';

Map<String, String> safeVariables(String text) {
  try {
    return (jsonDecode(text) as Map).map((k, v) => MapEntry('$k', '$v'));
  } catch (_) {
    return {};
  }
}

class WhatsAppTemplate {
  WhatsAppTemplate(Map<String, dynamic> data)
    : data = Map<String, dynamic>.from(data);
  final Map<String, dynamic> data;
  String get sid => '${data['sid'] ?? ''}';
  String get name => '${data['friendly_name'] ?? sid}';
  String get language => '${data['language'] ?? ''}';
  String get status => '${data['relay_status'] ?? 'unknown'}'.toLowerCase();
  Map<String, dynamic> get types =>
      Map<String, dynamic>.from(data['types'] ?? {});
  Map<String, dynamic> get content {
    for (final key in [
      'twilio/call-to-action',
      'twilio/card',
      'whatsapp/card',
      'twilio/media',
      'twilio/text',
      'twilio/quick-reply',
    ]) {
      if (types[key] is Map) return Map<String, dynamic>.from(types[key]);
    }
    return {};
  }

  String get body =>
      '${types.containsKey('twilio/card') && !types.containsKey('twilio/call-to-action') ? content['title'] ?? content['body'] ?? '' : content['body'] ?? ''}';
  List<String> get media =>
      (content['media'] as List? ?? []).map((v) => '$v').toList();
  List<Map<String, dynamic>> get links => (content['actions'] as List? ?? [])
      .whereType<Map>()
      .where((a) => a['type'] == 'URL')
      .map((a) => Map<String, dynamic>.from(a))
      .toList();
  Map<String, String> get samples =>
      Map<String, dynamic>.from(data['variables'] ?? {})
          .map((k, v) => MapEntry(k, '$v'));
  List<String> get slots {
    final found = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(jsonEncode(types))
        .map((m) => m[1]!)
        .toSet()
        .toList();
    found.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    return found;
  }

  String render(String text, Map<String, String> values, Contact c) =>
      text.replaceAllMapped(
        RegExp(r'\{\{(\d+)\}\}'),
        (m) => personal(values[m[1]] ?? samples[m[1]] ?? m[0]!, c),
      );
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}

class ContentFailure implements Exception {
  ContentFailure(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
  @override
  String toString() => message;
}

class TemplateApi {
  TemplateApi(this.client);
  final http.Client client;
  Future<Map<String, dynamic>> request(
    Settings s,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    if (!s.connected) {
      throw StateError(
        'احفظ بيانات Twilio أولاً / Save Twilio credentials first.',
      );
    }
    if (uri.scheme != 'https' ||
        uri.host != 'content.twilio.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw StateError('Invalid Twilio Content URL');
    }
    final user = s.authMode == 'token' ? s.accountSid : s.apiKeySid;
    final headers = {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$user:${s.secret}'))}',
      'Content-Type': 'application/json',
    };
    http.Response response;
    try {
      response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ContentFailure(
        'تعذر تأكيد الطلب. تحقق من قوالبك في Twilio قبل تكرار الحفظ. / Request uncertain. Check your Twilio templates before saving again.',
        uncertain: body != null,
      );
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (_) {
      throw ContentFailure(
        'Unexpected Twilio Content response. Check the console before repeating a creation request.',
        uncertain: body != null,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ContentFailure(
        '${data['message'] ?? 'Twilio Content error'}${[401, 403].contains(response.statusCode) ? ' / تحقق من صلاحية Content API لمفتاحك. Check Content API permissions.' : ''}',
        uncertain: body != null && response.statusCode >= 500,
      );
    }
    return data;
  }

  Uri uri(String path) => Uri.https('content.twilio.com', '/v1/$path');
  String checkSid(String sid) {
    if (!RegExp(r'^HX[0-9a-fA-F]{32}$').hasMatch(sid)) {
      throw const FormatException('Invalid Content SID');
    }
    return sid;
  }

  Future<List<WhatsAppTemplate>> list(Settings s) async {
    Uri? page = uri('ContentAndApprovals')
        .replace(queryParameters: {'PageSize': '100'});
    final templates = <WhatsAppTemplate>[];
    final seen = <String>{};
    while (page != null && seen.add(page.toString())) {
      final data = await request(s, page);
      for (final raw in data['contents'] as List? ?? []) {
        final row = Map<String, dynamic>.from(raw);
        // Approval is fetched separately on selection; never infer approval from existence.
        row['relay_status'] = 'unknown';
        templates.add(WhatsAppTemplate(row));
      }
      final next = data['meta']?['next_page_url'];
      page = next == null || '$next'.isEmpty ? null : Uri.parse('$next');
      if (templates.length >= 6000 && page != null) {
        throw StateError(
          'Too many templates. Use Twilio console to manage the list.',
        );
      }
    }
    templates.sort((a, b) => a.name.compareTo(b.name));
    return templates;
  }

  Future<WhatsAppTemplate> refresh(Settings s, WhatsAppTemplate value) async {
    final data = await request(
      s,
      uri('Content/${checkSid(value.sid)}/ApprovalRequests'),
    );
    final approval = data['whatsapp'] as Map? ?? {};
    return WhatsAppTemplate({
      ...value.data,
      'relay_status': approval['status'] ?? 'unsubmitted',
      'relay_reason': approval['rejection_reason'] ?? '',
    });
  }

  Future<WhatsAppTemplate> create(
    Settings s, {
    required String name,
    required String language,
    required String body,
    required Map<String, String> samples,
    required List<Map<String, String>> links,
    String mediaUrl = '',
  }) async {
    if (name.trim().isEmpty || name.length > 100) {
      throw const FormatException(
        'أدخل اسم القالب / Enter a template name (1–100 characters).',
      );
    }
    if (!['ar', 'en'].contains(language)) {
      throw const FormatException('Choose Arabic or English.');
    }
    if (body.trim().isEmpty || body.length > (links.isEmpty ? 1600 : 640)) {
      throw const FormatException(
        'النص مطلوب: حتى 640 حرفاً مع الأزرار أو 1600 بدونها / Body required: up to 640 characters with buttons, 1600 without.',
      );
    }
    if (links.length > 2) {
      throw const FormatException(
        'زرّا رابط كحد أقصى / Maximum two website buttons.',
      );
    }
    if (mediaUrl.isNotEmpty &&
        (!isPublicHttps(mediaUrl) || mediaUrl.contains('{{'))) {
      throw const FormatException(
        'أضف رابط HTTPS عاماً لصورة ثابتة / Use a full public HTTPS photo URL.',
      );
    }
    for (final link in links) {
      if (link['title']!.trim().isEmpty ||
          link['title']!.runes.length > 20 ||
          link['title']!.contains('{{') ||
          !isPublicHttps(link['url']!) ||
          link['url']!.contains('{{')) {
        throw const FormatException(
          'لكل زر: عنوان حتى 20 حرفاً ورابط HTTPS كامل / Each button needs a label up to 20 characters and a full HTTPS link.',
        );
      }
    }
    final slots = RegExp(r'\{\{(\d+)\}\}')
        .allMatches(body)
        .map((m) => m[1]!)
        .toSet();
    if (body
        .replaceAll(RegExp(r'\{\{\d+\}\}'), '')
        .contains(RegExp(r'\{\{|\}\}'))) {
      throw const FormatException(
        'استخدم زر إضافة متغير أو {{1}}، {{2}}… / Use Add variable or {{1}}, {{2}}…',
      );
    }
    final ordered = slots.map(int.parse).toList()..sort();
    for (var n = 0; n < ordered.length; n++) {
      if (ordered[n] != n + 1 ||
          (samples['${n + 1}'] ?? '').trim().isEmpty ||
          samples['${n + 1}']!.contains('{{')) {
        throw const FormatException(
          'أضف مثالاً لكل متغير وبالترتيب 1، 2… / Provide a sample for each variable, numbered 1, 2…',
        );
      }
    }
    final content = {
      mediaUrl.isNotEmpty && links.isNotEmpty ? 'title' : 'body': body.trim(),
      if (mediaUrl.isNotEmpty) 'media': [mediaUrl.trim()],
      if (links.isNotEmpty)
        'actions': [
          for (final l in links)
            {
              'type': 'URL',
              'title': l['title']!.trim(),
              'url': l['url']!.trim(),
            },
        ],
    };
    final data = await request(
      s,
      uri('Content'),
      body: {
        'friendly_name': name.trim(),
        'language': language,
        'variables': {for (final slot in slots) slot: samples[slot]},
        'types': {
          mediaUrl.isNotEmpty
                  ? (links.isEmpty ? 'twilio/media' : 'twilio/card')
                  : (links.isEmpty ? 'twilio/text' : 'twilio/call-to-action'):
              content,
        },
      },
    );
    try {
      checkSid('${data['sid']}');
    } catch (_) {
      throw ContentFailure(
        'Template creation response had no valid Content SID. Check Twilio before saving again.',
        uncertain: true,
      );
    }
    return WhatsAppTemplate({...data, 'relay_status': 'unsubmitted'});
  }

  Future<WhatsAppTemplate> submit(
    Settings s,
    WhatsAppTemplate value,
    String approvalName,
    String category,
  ) async {
    if (!RegExp(r'^[a-z0-9_]{1,512}$').hasMatch(approvalName) ||
        !['UTILITY', 'MARKETING'].contains(category)) {
      throw const FormatException(
        'Approval name needs lowercase English letters, numbers or underscores.',
      );
    }
    final response = await request(
      s,
      uri('Content/${checkSid(value.sid)}/ApprovalRequests/whatsapp'),
      body: {'name': approvalName, 'category': category},
    );
    return WhatsAppTemplate({
      ...value.data,
      'relay_status': response['status'] ?? 'received',
      'relay_reason': response['rejection_reason'] ?? '',
    });
  }
}
