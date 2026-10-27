import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'domain.dart';
import 'photo_probe.dart';

class AssetUploadException implements Exception {
  AssetUploadException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class TwilioAssets {
  TwilioAssets(
    this.client, {
    this.pollInterval = const Duration(seconds: 1),
    this.pollLimit = 120,
    this.publicCheckAttempts = 30,
  });
  final http.Client client;
  final Duration pollInterval;
  final int pollLimit;
  final int publicCheckAttempts;
  Map<String, String> auth(Settings s) => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('${s.authMode == 'token' ? s.accountSid : s.apiKeySid}:${s.secret}'))}',
  };
  String sid(String prefix, Object? value) {
    final text = value?.toString() ?? '';
    if (!RegExp('^$prefix[0-9a-fA-F]{32}\$').hasMatch(text)) {
      throw AssetUploadException(
        'Twilio returned an invalid resource identifier.',
      );
    }
    return text;
  }

  Map<String, dynamic> decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (_) {
      throw AssetUploadException(
        'استجابة غير متوقعة من Twilio / Unexpected Twilio response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final help = [401, 403].contains(response.statusCode)
          ? ' تحتاج صلاحية Twilio Functions & Assets. استخدم مفتاح Standard أو Auth Token. / Functions & Assets access is required; use a Standard key or Auth Token.'
          : '';
      throw AssetUploadException(
        '${data['message'] ?? 'Twilio Assets request failed'}$help',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> request(
    Settings s,
    String path, {
    List<MapEntry<String, String>>? fields,
  }) async {
    final uri = Uri.https('serverless.twilio.com', '/v1$path');
    try {
      if (fields == null) {
        return decode(
          await client
              .get(uri, headers: auth(s))
              .timeout(const Duration(seconds: 30)),
        );
      }
      final encoded = fields
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      return decode(
        await client
            .post(
              uri,
              headers: {
                ...auth(s),
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: encoded,
            )
            .timeout(const Duration(seconds: 45)),
      );
    } on AssetUploadException {
      rethrow;
    } catch (_) {
      throw AssetUploadException(
        'تعذر تأكيد عملية Twilio Assets. لم تُرسل رسالة. / Could not confirm the Assets operation. No message was sent.',
      );
    }
  }

  Future<String> upload(
    Settings s,
    Uint8List bytes,
    String name, {
    required Future<void> Function() persistConfiguration,
    void Function(String)? onProgress,
  }) async {
    String tr(String ar, String en) => s.language == 'en' ? en : ar;
    void phase(String ar, String en) => onProgress?.call(tr(ar, en));
    if (!s.connected) {
      throw AssetUploadException(
        tr('احفظ بيانات Twilio أولاً.', 'Save Twilio credentials first.'),
      );
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw AssetUploadException('5 MB maximum');
    }
    final png =
        bytes.length > 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final jpg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
    if (!png && !jpg) throw AssetUploadException('JPG / PNG only');
    if (s.mediaAccountSid != s.accountSid) {
      s.mediaServiceSid = '';
      s.mediaEnvironmentSid = '';
      s.mediaAccountSid = s.accountSid;
      s.lastPhotoUrl = '';
      s.lastPhotoError = '';
      s.lastPhotoPending = false;
    }
    phase('تهيئة مساحة الصور في Twilio…', 'Preparing Twilio photo space…');
    if (s.mediaServiceSid.isEmpty) {
      final service = await request(
        s,
        '/Services',
        fields: [
          MapEntry('FriendlyName', 'Relay WhatsApp photos'),
          MapEntry('UniqueName', 'relay-media-${newId()}'),
          const MapEntry('IncludeCredentials', 'false'),
          const MapEntry('UiEditable', 'true'),
        ],
      );
      s.mediaServiceSid = sid('ZS', service['sid']);
      await persistConfiguration();
    }
    final service = sid('ZS', s.mediaServiceSid);
    if (s.mediaEnvironmentSid.isEmpty) {
      Map<String, dynamic> environment;
      try {
        environment = await request(
          s,
          '/Services/$service/Environments',
          fields: [
            const MapEntry('UniqueName', 'photos'),
            const MapEntry('DomainSuffix', 'photos'),
          ],
        );
      } on AssetUploadException catch (e) {
        // Recover the environment when creation succeeded before an earlier interruption.
        if (e.statusCode != 409) rethrow;
        environment = await request(
          s,
          '/Services/$service/Environments/photos',
        );
      }
      s.mediaEnvironmentSid = sid('ZE', environment['sid']);
      await persistConfiguration();
    }
    final env = sid('ZE', s.mediaEnvironmentSid),
        envPath = '/Services/$service/Environments/${s.mediaEnvironmentSid}';
    final environment = await request(s, envPath);
    final domain = '${environment['domain_name'] ?? ''}';
    if (!RegExp(r'^[a-z0-9-]+\.twil\.io$').hasMatch(domain)) {
      throw AssetUploadException('Invalid Twilio asset domain');
    }
    final oldBuild = environment['build_sid']?.toString();
    final previous = <String>[];
    if (oldBuild != null && oldBuild.isNotEmpty) {
      final build = await request(
        s,
        '/Services/$service/Builds/${sid('ZB', oldBuild)}',
      );
      if ((build['function_versions'] as List? ?? []).isNotEmpty) {
        throw AssetUploadException(
          'مساحة الصور تحتوي Functions. لم يتم تعديلها. / This space contains Functions and will not be changed.',
        );
      }
      for (final item in build['asset_versions'] as List? ?? []) {
        previous.add(sid('ZN', item is Map ? item['sid'] : item));
      }
    }
    if (previous.length >= 1000) {
      throw AssetUploadException(
        'وصلت مساحة الصور إلى حد Twilio: 1,000 صورة. / This photo space reached Twilio’s 1,000-asset limit.',
      );
    }
    phase('رفع الصورة إلى Twilio…', 'Uploading photo to Twilio…');
    final asset = await request(
      s,
      '/Services/$service/Assets',
      fields: [
        MapEntry(
          'FriendlyName',
          name.length > 200 ? name.substring(0, 200) : name,
        ),
      ],
    );
    final assetSid = sid('ZH', asset['sid']);
    final photoPath = '/photos/${newId()}.${png ? 'png' : 'jpg'}';
    final upload =
        http.MultipartRequest(
            'POST',
            Uri.https(
              'serverless-upload.twilio.com',
              '/v1/Services/$service/Assets/$assetSid/Versions',
            ),
          )
          ..headers.addAll(auth(s))
          ..fields.addAll({'Path': photoPath, 'Visibility': 'public'})
          ..files.add(
            http.MultipartFile.fromBytes(
              'Content',
              bytes,
              filename: png ? 'photo.png' : 'photo.jpg',
              contentType: MediaType('image', png ? 'png' : 'jpeg'),
            ),
          );
    final version = decode(
      await http.Response.fromStream(
        await client.send(upload).timeout(const Duration(seconds: 60)),
      ).timeout(const Duration(seconds: 60)),
    );
    final versionSid = sid('ZN', version['sid']);
    phase(
      'نشر الصورة — قد يستغرق دقيقة…',
      'Publishing photo — this may take a minute…',
    );
    final build = await request(
      s,
      '/Services/$service/Builds',
      fields: [
        ...previous.map((id) => MapEntry('AssetVersions', id)),
        MapEntry('AssetVersions', versionSid),
        const MapEntry('Dependencies', '[]'),
        const MapEntry('Runtime', 'node22'),
      ],
    );
    final buildSid = sid('ZB', build['sid']);
    var complete = '${build['status']}'.toLowerCase() == 'completed';
    for (var n = 0; !complete && n < pollLimit; n++) {
      final status = await request(
        s,
        '/Services/$service/Builds/$buildSid/Status',
      );
      final value = '${status['status']}'.toLowerCase();
      if (value == 'failed') {
        throw AssetUploadException(
          'فشل نشر الصورة في Twilio؛ لم يتغير النشر السابق. / Twilio photo build failed; previous deployment is unchanged.',
        );
      }
      complete = value == 'completed';
      if (!complete) await Future<void>.delayed(pollInterval);
    }
    if (!complete) {
      throw AssetUploadException(
        'انتهت مهلة النشر. لم تُرسل رسالة. / Photo build timed out. No message was sent.',
      );
    }
    // Do not overwrite a deployment changed by another device during the build.
    final current = await request(s, envPath);
    if ((current['build_sid']?.toString() ?? '') != (oldBuild ?? '')) {
      throw AssetUploadException(
        'مساحة الصور تغيرت أثناء الرفع. أعد المحاولة. / Photo space changed during upload. Please try again.',
      );
    }
    await request(
      s,
      '/Services/$service/Environments/$env/Deployments',
      fields: [MapEntry('BuildSid', buildSid)],
    );
    final url = Uri.https(domain, photoPath);
    // Persist before checking the public endpoint, including when propagation,
    // connectivity or MIME verification fails. Retrying must not upload again.
    s.lastPhotoUrl = url.toString();
    s.lastPhotoPending = true;
    s.lastPhotoError = '';
    await persistConfiguration();
    phase('التحقق من رابط الصورة…', 'Checking the public image URL…');
    try {
      final result = await PublicPhotoProbe(
        client,
        attempts: publicCheckAttempts,
        interval: pollInterval * 2,
      ).verify(url.toString(), onProgress: onProgress, language: s.language);
      s.lastPhotoPending = false;
      await persistConfiguration();
      return result;
    } on PhotoCheckFailure catch (e) {
      s.lastPhotoError = e.detail;
      await persistConfiguration();
      rethrow;
    }
  }
}
