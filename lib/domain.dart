import 'dart:convert';
import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

String? normalizePhone(Object? value, [String code = '964']) {
  var s = (value ?? '').toString().trim().replaceFirst(RegExp(r"^'"), '');
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  s = s
      .split('')
      .map(
        (c) => arabic.contains(c)
            ? '${arabic.indexOf(c)}'
            : persian.contains(c)
            ? '${persian.indexOf(c)}'
            : c,
      )
      .join();
  s = s
      .replaceFirst(RegExp(r'^whatsapp:', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s().-]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (!s.startsWith('+')) {
    s = s.replaceFirst(RegExp(r'^0'), '');
    s = s.startsWith(code) ? '+$s' : '+$code$s';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s) ? s : null;
}

List<List<String>> parseCsv(String input) {
  final text = input.replaceFirst('\uFEFF', '');
  final first = text.split(RegExp(r'\r?\n')).first;
  final delimiter = ','.allMatches(first).length < ';'.allMatches(first).length
      ? ';'
      : first.contains('\t')
      ? '\t'
      : ',';
  final rows = <List<String>>[];
  var row = <String>[], cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && c == delimiter) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if (!quoted && (c == '\r' || c == '\n')) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
      row = [];
      cell = StringBuffer();
    } else {
      cell.write(c);
    }
  }
  if (quoted) {
    throw const FormatException('CSV: unclosed quote / علامة اقتباس غير مغلقة');
  }
  row.add(cell.toString());
  if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
  return rows;
}

String csvCell(Object? value) {
  var s = (value ?? '').toString();
  if (RegExp(r'^[=+\-@\t\r]').hasMatch(s)) s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

String csvFile(List<List<Object?>> rows) =>
    '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}';
String personal(String text, Contact c) => text.replaceAllMapped(
  RegExp(r'\{\{\s*(name|phone)\s*\}\}'),
  (m) => m[1] == 'name' ? c.name : c.phone,
);

class Contact {
  Contact({
    String? id,
    required this.name,
    required this.phone,
    this.consent = false,
    this.selected = true,
  }) : id = id ?? newId();
  final String id;
  String name, phone;
  bool consent, selected;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'consent': consent,
    'selected': selected,
  };
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
    id: j['id'],
    name: j['name'] ?? '',
    phone: j['phone'],
    consent: j['consent'] == true,
    selected: j['selected'] != false,
  );
}

class Settings {
  String brand = 'Relay', language = 'ar', countryCode = '964';
  String accountSid = '',
      sender = '',
      apiKeySid = '',
      secret = '',
      authMode = 'key';
  String mediaServiceSid = '', mediaEnvironmentSid = '', mediaAccountSid = '';
  String lastPhotoUrl = '', lastPhotoError = '';
  bool lastPhotoPending = false;
  bool get connected =>
      RegExp(r'^AC[0-9a-f]{32}$', caseSensitive: false).hasMatch(accountSid) &&
      normalizePhone(sender) == sender &&
      secret.isNotEmpty &&
      (authMode == 'token' ||
          RegExp(
            r'^SK[0-9a-f]{32}$',
            caseSensitive: false,
          ).hasMatch(apiKeySid));
  bool get canUpload => connected;
  Map<String, dynamic> toJson() => {
    'brand': brand,
    'language': language,
    'countryCode': countryCode,
    'accountSid': accountSid,
    'sender': sender,
    'apiKeySid': apiKeySid,
    'authMode': authMode,
    'mediaServiceSid': mediaServiceSid,
    'mediaEnvironmentSid': mediaEnvironmentSid,
    'mediaAccountSid': mediaAccountSid,
    'lastPhotoUrl': lastPhotoUrl,
    'lastPhotoError': lastPhotoError,
    'lastPhotoPending': lastPhotoPending,
  };
  Map<String, String> secrets() => {'secret': secret};
  factory Settings.fromJson(
    Map<String, dynamic> j, [
    Map<String, dynamic> secrets = const {},
  ]) => Settings()
    ..brand = j['brand'] ?? 'Relay'
    ..language = j['language'] == 'en' ? 'en' : 'ar'
    ..countryCode = j['countryCode'] ?? '964'
    ..accountSid = j['accountSid'] ?? ''
    ..sender = j['sender'] ?? ''
    ..apiKeySid = j['apiKeySid'] ?? ''
    ..authMode = j['authMode'] == 'token' ? 'token' : 'key'
    ..mediaServiceSid = j['mediaServiceSid'] ?? ''
    ..mediaEnvironmentSid = j['mediaEnvironmentSid'] ?? ''
    ..mediaAccountSid = j['mediaAccountSid'] ?? ''
    ..lastPhotoUrl = j['lastPhotoUrl'] ?? ''
    ..lastPhotoError = j['lastPhotoError'] ?? ''
    ..lastPhotoPending = j['lastPhotoPending'] == true
    ..secret = secrets['secret'] ?? '';
  Settings();
  Settings copy() => Settings.fromJson(toJson(), secrets());
}

class Draft {
  Map<String, dynamic> templateData = {};
  String name = '',
      body = '',
      contentSid = '',
      variables = '{"1":"{{name}}"}',
      mediaUrl = '';
  bool template = true;
  Draft();
  Map<String, dynamic> toJson() => {
    'templateData': templateData,
    'name': name,
    'body': body,
    'contentSid': contentSid,
    'variables': variables,
    'mediaUrl': mediaUrl,
    'template': template,
  };
  factory Draft.fromJson(Map<String, dynamic> j) => Draft()
    ..templateData = Map<String, dynamic>.from(j['templateData'] ?? {})
    ..name = j['name'] ?? ''
    ..body = j['body'] ?? ''
    ..contentSid = j['contentSid'] ?? ''
    ..variables = j['variables'] ?? '{}'
    ..mediaUrl = j['mediaUrl'] ?? ''
    ..template = j['template'] != false;
  Draft copy() => Draft.fromJson(toJson());
  Map<String, String> parsedVariables() {
    final Object? raw = jsonDecode(variables.trim().isEmpty ? '{}' : variables);
    if (raw is! Map ||
        raw.entries.any(
          (e) =>
              !RegExp(r'^\d+$').hasMatch(e.key.toString()) ||
              e.value is! String ||
              (e.value as String).length > 2000,
        )) {
      throw const FormatException(
        'متغيرات القالب: مفاتيح رقمية وقيم نصية / Variables need numeric keys and text values.',
      );
    }
    return raw.map((k, v) => MapEntry(k.toString(), v as String));
  }
}

class Attempt {
  Attempt({
    required this.contactId,
    this.status = 'submitting',
    this.sid = '',
    this.error = '',
    this.code = '',
  });
  final String contactId;
  String status, sid, error, code;
  Map<String, dynamic> toJson() => {
    'contactId': contactId,
    'status': status,
    'sid': sid,
    'error': error,
    'code': code,
  };
  factory Attempt.fromJson(Map<String, dynamic> j) => Attempt(
    contactId: j['contactId'],
    status: j['status'] ?? 'unknown',
    sid: j['sid'] ?? '',
    error: j['error'] ?? '',
    code: '${j['code'] ?? ''}',
  );
}

class SendRun {
  SendRun({
    String? id,
    required this.name,
    required this.sender,
    required this.accountSid,
    required this.draft,
    required this.contacts,
  }) : id = id ?? newId();
  final String id, name, sender, accountSid;
  final Draft draft;
  final List<Contact> contacts;
  DateTime created = DateTime.now();
  final Map<String, Attempt> attempts = {};
  Iterable<Contact> get pending =>
      contacts.where((c) => !attempts.containsKey(c.id));
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sender': sender,
    'accountSid': accountSid,
    'draft': draft.toJson(),
    'contacts': contacts.map((c) => c.toJson()).toList(),
    'created': created.toIso8601String(),
    'attempts': attempts.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory SendRun.fromJson(Map<String, dynamic> j) {
    final r = SendRun(
      id: j['id'],
      name: j['name'],
      sender: j['sender'],
      accountSid: j['accountSid'],
      draft: Draft.fromJson(Map<String, dynamic>.from(j['draft'])),
      contacts: (j['contacts'] as List)
          .map((c) => Contact.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
    );
    r.created = DateTime.parse(j['created']);
    (j['attempts'] as Map? ?? {}).forEach(
      (k, v) => r.attempts[k] = Attempt.fromJson(Map<String, dynamic>.from(v)),
    );
    return r;
  }
}

class ImportResult {
  final contacts = <Contact>[];
  final invalidRows = <int>[];
  int duplicates = 0;
}

ImportResult mapContacts(
  List<List<String>> rows,
  int phoneCol,
  int nameCol,
  int consentCol,
  String code,
  Iterable<Contact> existing, {
  bool allConsent = false,
}) {
  final r = ImportResult(), seen = existing.map((c) => c.phone).toSet();
  String cell(List<String> row, int i) =>
      i >= 0 && i < row.length ? row[i].trim() : '';
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.every((c) => c.trim().isEmpty)) continue;
    final phone = normalizePhone(cell(row, phoneCol), code);
    if (phone == null) {
      r.invalidRows.add(i + 1);
      continue;
    }
    if (!seen.add(phone)) {
      r.duplicates++;
      continue;
    }
    r.contacts.add(
      Contact(
        name: cell(row, nameCol),
        phone: phone,
        consent:
            allConsent ||
            [
              'yes',
              'true',
              '1',
              'نعم',
            ].contains(cell(row, consentCol).toLowerCase()),
      ),
    );
  }
  return r;
}

bool isPublicHttps(String value) {
  final u = Uri.tryParse(value.trim());
  if (u == null ||
      u.scheme != 'https' ||
      !u.hasAuthority ||
      u.userInfo.isNotEmpty) {
    return false;
  }
  final host = u.host.toLowerCase();
  return host.contains('.') &&
      host != 'localhost' &&
      !RegExp(
        r'^(127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(1[6-9]|2\d|3[01])\.)',
      ).hasMatch(host);
}
