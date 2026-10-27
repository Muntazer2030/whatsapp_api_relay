import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'twilio_assets.dart';

import 'package:excel/excel.dart';
import 'package:excel2003/excel2003.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'domain.dart';
import 'photo_probe.dart';

abstract class Repository {
  Future<Map<String, dynamic>> load();
  Future<void> save(Map<String, dynamic> data);
  Future<Map<String, dynamic>> loadSecrets();
  Future<void> saveSecrets(Map<String, String> data);
}

class DeviceRepository implements Repository {
  DeviceRepository({
    this.directory,
    this.credentialsKey = 'relay.credentials.v1',
  });
  final Directory? directory;
  final String credentialsKey;
  Directory? _dir;
  RandomAccessFile? _lock;
  Future<void> _writes = Future.value();
  final FlutterSecureStorage vault = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage();

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final root = directory ?? await getApplicationSupportDirectory();
    final dir = await Directory('${root.path}/Relay').create(recursive: true);
    final lock = await File('${dir.path}/instance.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw StateError(
        'التطبيق مفتوح بالفعل أو لا يمكن قفل التخزين / Another instance is open or storage cannot be locked.',
      );
    }
    _lock = lock;
    _dir = dir;
    return dir;
  }

  @override
  Future<Map<String, dynamic>> load() async {
    final dir = await _directory();
    for (final name in ['state.json', 'state.backup.json']) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) {
        try {
          return Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()),
          );
        } catch (_) {
          if (name == 'state.backup.json' ||
              !await File('${dir.path}/state.backup.json').exists()) {
            rethrow;
          }
        }
      }
    }
    return {};
  }

  @override
  Future<void> save(Map<String, dynamic> data) {
    final snapshot = jsonEncode(data);
    final done = _writes.catchError((Object _) {}).then((_) async {
      final dir = await _directory();
      final live = File('${dir.path}/state.json'),
          backup = File('${dir.path}/state.backup.json');
      final temp = File('${dir.path}/state.tmp.json');
      await temp.writeAsString(snapshot, flush: true);
      if (await live.exists()) {
        if (await backup.exists()) await backup.delete();
        await live.rename(backup.path);
      }
      await temp.rename(live.path);
    });
    _writes = done;
    return done;
  }

  @override
  Future<Map<String, dynamic>> loadSecrets() async {
    final text = await vault.read(key: credentialsKey);
    return text == null ? {} : Map<String, dynamic>.from(jsonDecode(text));
  }

  @override
  Future<void> saveSecrets(Map<String, String> data) =>
      vault.write(key: credentialsKey, value: jsonEncode(data));

  Future<void> close() async {
    await _writes;
    await _lock?.unlock();
    await _lock?.close();
  }
}

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.code = '', this.uncertain = false});
  final String message, code;
  final bool uncertain;
  @override
  String toString() => code.isEmpty ? message : '$message ($code)';
}

class TwilioApi {
  TwilioApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<String> verifyPhoto(
    Settings s,
    String url, {
    void Function(String)? onProgress,
  }) =>
      PublicPhotoProbe(client)
          .verify(url, onProgress: onProgress, language: s.language);
  Future<Map<String, dynamic>> request(
    Settings s,
    String path, {
    Map<String, String>? fields,
  }) async {
    if (!s.connected) {
      throw ApiFailure(
        'أكمل بيانات Twilio في الإعدادات / Complete Twilio Settings.',
      );
    }
    final user = s.authMode == 'token' ? s.accountSid : s.apiKeySid;
    final uri = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/${s.accountSid}$path',
    );
    final headers = {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$user:${s.secret}'))}',
    };
    http.Response response;
    try {
      response =
          await (fields == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: fields))
              .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw ApiFailure(
        'تعذر تأكيد الطلب. افحص سجل Twilio قبل إعادة الإرسال / Response uncertain. Check Twilio logs before resending.',
        uncertain: fields != null,
      );
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (_) {
      throw ApiFailure(
        'استجابة غير متوقعة من Twilio / Unexpected Twilio response.',
        uncertain: fields != null,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiFailure(
        'Twilio server error. Check logs before resending.',
        uncertain: fields != null,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        data['message']?.toString() ?? 'Twilio error',
        code: '${data['code'] ?? response.statusCode}',
      );
    }
    return data;
  }

  Future<void> test(Settings s) async {
    await request(s, '/Messages.json?PageSize=1');
  }

  Future<Attempt> send(Settings s, SendRun run, Contact c) async {
    final fields = <String, String>{
      'To': 'whatsapp:${c.phone}',
      'From': 'whatsapp:${run.sender}',
    };
    if (run.draft.template) {
      fields['ContentSid'] = run.draft.contentSid.trim();
      final variables = run.draft.parsedVariables().map(
        (k, v) => MapEntry(k, personal(v, c)),
      );
      if (variables.isNotEmpty) {
        fields['ContentVariables'] = jsonEncode(variables);
      }
    } else {
      if (run.draft.body.trim().isNotEmpty) {
        fields['Body'] = personal(run.draft.body, c);
      }
      if (run.draft.mediaUrl.trim().isNotEmpty) {
        fields['MediaUrl'] = run.draft.mediaUrl.trim();
      }
    }
    final data = await request(s, '/Messages.json', fields: fields);
    final sid = data['sid']?.toString() ?? '';
    if (!RegExp(r'^(SM|MM)[0-9a-f]{32}$', caseSensitive: false).hasMatch(sid)) {
      throw ApiFailure(
        'Twilio returned no message SID. Check logs.',
        uncertain: true,
      );
    }
    return Attempt(
      contactId: c.id,
      sid: sid,
      status: data['status'] ?? 'queued',
      code: '${data['error_code'] ?? ''}',
    );
  }

  Future<Attempt> refresh(Settings s, Attempt a) async {
    final data = await request(s, '/Messages/${a.sid}.json');
    return Attempt(
      contactId: a.contactId,
      sid: a.sid,
      status: data['status'] ?? a.status,
      error: data['error_message'] ?? '',
      code: '${data['error_code'] ?? ''}',
    );
  }

  Future<String> upload(
    Settings s,
    Uint8List bytes,
    String name, {
    required Future<void> Function() persistConfiguration,
    void Function(String)? onProgress,
  }) => TwilioAssets(client).upload(
    s,
    bytes,
    name,
    persistConfiguration: persistConfiguration,
    onProgress: onProgress,
  );
}

// The parser runs in an isolate so spreadsheets do not freeze the interface.
Map<String, List<List<String>>> decodeWorkbook(Map<String, Object> payload) {
  final bytes = payload['bytes'] as Uint8List,
      ext = payload['extension'] as String;
  final result = <String, List<List<String>>>{};
  if (ext == 'csv') {
    result['CSV'] = parseCsv(utf8.decode(bytes));
  } else if (ext == 'xls') {
    final reader = XlsReader.fromBytes(bytes);
    reader.open();
    for (var i = 0; i < reader.sheetCount; i++) {
      final sheet = reader.sheet(i);
      if (sheet.lastRow - sheet.firstRow > 5001 ||
          sheet.lastCol - sheet.firstCol > 100) {
        throw const FormatException(
          'Maximum: 5,000 contacts / الحد الأقصى 5,000 جهة اتصال',
        );
      }
      result[reader.sheetNames[i]] = [
        for (var r = sheet.firstRow; r < sheet.lastRow; r++)
          [
            for (var c = sheet.firstCol; c < sheet.lastCol; c++)
              '${sheet.cell(r, c) ?? ''}',
          ],
      ];
    }
  } else {
    final book = Excel.decodeBytes(bytes);
    for (final entry in book.tables.entries) {
      if (entry.value.maxRows > 5001 || entry.value.maxColumns > 100) {
        throw const FormatException(
          'Maximum: 5,000 contacts / الحد الأقصى 5,000 جهة اتصال',
        );
      }
      result[entry.key] = entry.value.rows
          .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
    }
  }
  result.removeWhere((k, v) => v.length < 2);
  if (result.isEmpty) {
    throw const FormatException(
      'أضف عناوين أعمدة وصف بيانات على الأقل / Include column headers and at least one data row.',
    );
  }
  if (result.values.any((v) => v.length > 5001)) {
    throw const FormatException('Maximum: 5,000 contacts');
  }
  return result;
}

Future<Map<String, List<List<String>>>> readWorkbook(
  Uint8List bytes,
  String extension,
) => compute(decodeWorkbook, {'bytes': bytes, 'extension': extension});
