import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_native/controller.dart';
import 'package:relay_native/domain.dart';
import 'package:relay_native/services.dart';

import 'helpers.dart';

Settings credentials() => Settings()
  ..accountSid = 'AC${'1' * 32}'
  ..apiKeySid = 'SK${'2' * 32}'
  ..secret = 'fake-test-secret'
  ..sender = '+9647700000000';
Future<RelayController> setup(MemoryRepository repo, TwilioApi api) async {
  final c = RelayController(repository: repo, api: api);
  await c.initialize();
  await c.saveSettings(credentials());
  await c.addContacts([
    Contact(name: 'Ali', phone: '+9647701234567', consent: true),
  ]);
  return c;
}

Draft template() => Draft()
  ..contentSid = 'HX${'3' * 32}'
  ..variables = '{"1":"{{name}}"}';

void main() {
  test('legacy XLS imports an actual synthetic BIFF8/OLE workbook', () {
    final book = decodeWorkbook({
      'bytes': File('examples/contacts.xls').readAsBytesSync(),
      'extension': 'xls',
    });
    expect(book['Contacts']![1][1], '07701234567');
    final result = mapContacts(book['Contacts']!, 1, 0, 2, '964', []);
    expect(result.contacts.single.phone, '+9647701234567');
    expect(result.contacts.single.consent, false);
  });
  test('normalizes Iraqi local/international/Arabic/Persian numbers', () {
    for (final value in [
      '0770 123 4567',
      '009647701234567',
      '+9647701234567',
      '٠٧٧٠١٢٣٤٥٦٧',
      '۰۷۷۰۱۲۳۴۵۶۷',
      "'+9647701234567",
    ]) {
      expect(normalizePhone(value), '+9647701234567');
    }
    expect(normalizePhone('abc'), isNull);
    expect(normalizePhone('123'), isNull);
  });
  test(
    'CSV handles BOM, quoting, multiline, semicolon and consent defaults',
    () {
      final rows = parseCsv(
        '\uFEFFname,phone,consent\r\n"Ali, A",07701234567,yes\r\n"A""B\nC",07801234567,no\r\nDuplicate,+9647701234567,yes\r\nBad,xyz,yes',
      );
      final result = mapContacts(rows, 1, 0, 2, '964', []);
      expect(result.contacts.length, 2);
      expect(result.contacts.first.name, 'Ali, A');
      expect(result.contacts.last.consent, false);
      expect(result.duplicates, 1);
      expect(result.invalidRows, [5]);
      expect(parseCsv('name;phone\nAli;07701234567')[1][0], 'Ali');
      expect(() => parseCsv('"open'), throwsFormatException);
    },
  );
  test(
    'CSV export protects formulas and can reimport international phones',
    () {
      final rows = parseCsv(
        csvFile([
          ['name', 'phone'],
          ['=SUM(1)', '+9647701234567'],
        ]),
      );
      expect(rows[1][0], "'=SUM(1)");
      expect(normalizePhone(rows[1][1]), '+9647701234567');
    },
  );
  test('XLSX workbook parses actual bytes and keeps text phone numbers', () {
    final book = Excel.createExcel(), sheet = book['Sheet1'];
    sheet.appendRow([
      TextCellValue('name'),
      TextCellValue('phone'),
      TextCellValue('consent'),
    ]);
    sheet.appendRow([
      TextCellValue('Ali'),
      TextCellValue('07701234567'),
      TextCellValue('yes'),
    ]);
    final result = decodeWorkbook({
      'bytes': Uint8List.fromList(book.encode()!),
      'extension': 'xlsx',
    });
    expect(result['Sheet1']![1][1], '07701234567');
  });
  test(
    'secrets are separated from saved contacts/history and survive reload',
    () async {
      final repo = MemoryRepository(),
          c = RelayController(repository: MemoryRepository());
      final app = RelayController(repository: repo);
      await app.initialize();
      expect(app.settings.language, 'ar');
      expect(app.settings.countryCode, '964');
      await app.saveSettings(credentials());
      expect(jsonEncode(repo.state), isNot(contains('fake-test-secret')));
      final reopened = RelayController(repository: repo);
      await reopened.initialize();
      expect(reopened.settings.connected, true);
      expect(reopened.settings.secret, 'fake-test-secret');
      c.dispose();
      app.dispose();
      reopened.dispose();
    },
  );
  test('consent, approval SID, JSON and session-window validation', () async {
    final c = RelayController(repository: MemoryRepository());
    await c.initialize();
    await c.saveSettings(credentials());
    final p = Contact(name: 'Ali', phone: '+9647701234567');
    expect(
      () => c.validateDraft(template(), [p], true, false),
      throwsStateError,
    );
    p.consent = true;
    expect(
      () => c.validateDraft(template(), [p], false, false),
      throwsStateError,
    );
    expect(
      () => c.validateDraft(
        Draft()
          ..template = false
          ..body = 'hi',
        [p],
        true,
        false,
      ),
      throwsStateError,
    );
    expect(
      () => (template()..variables = '[]').parsedVariables(),
      throwsFormatException,
    );
    expect(isPublicHttps('https://localhost/a.jpg'), false);
    expect(isPublicHttps('https://10.0.0.1/a.jpg'), false);
  });
  test('durable claim precedes API submission; duplicates and concurrent starts do not resend', () async {
    final repo = MemoryRepository();
    var sends = 0;
    final c = await setup(
      repo,
      TwilioApi(
        client: MockClient((request) async {
          sends++;
          final attempt =
              ((repo.state['runs'] as List).first['attempts'] as Map)
                  .values
                  .first;
          expect(attempt['status'], 'submitting');
          final fields = Uri.splitQueryString(request.body);
          expect(fields['To'], 'whatsapp:+9647701234567');
          expect(jsonDecode(fields['ContentVariables']!), {'1': 'Ali'});
          return http.Response(
            jsonEncode({'sid': 'SM${'4' * 32}', 'status': 'queued'}),
            201,
          );
        }),
      ),
    );
    final run = await c.createRun(template(), c.contacts, true, false);
    await Future.wait([
      c.process(run, interval: Duration.zero),
      c.process(run, interval: Duration.zero),
    ]);
    await c.process(run, interval: Duration.zero);
    expect(sends, 1);
    expect(run.attempts.values.single.status, 'queued');
  });
  test(
    'uncertain network outcome persists and is never automatically retried',
    () async {
      var sends = 0;
      final repo = MemoryRepository();
      final c = await setup(
        repo,
        TwilioApi(
          client: MockClient((_) async {
            sends++;
            throw const SocketException('timeout');
          }),
        ),
      );
      final run = await c.createRun(template(), c.contacts, true, false);
      await c.process(run, interval: Duration.zero);
      expect(run.attempts.values.single.status, 'unknown');
      expect(c.paused, true);
      final reopened = RelayController(repository: repo, api: c.api);
      await reopened.initialize();
      await reopened.process(reopened.runs.single, interval: Duration.zero);
      expect(sends, 1);
    },
  );
  test(
    'storage failure prevents sending and does not lose recorded intent',
    () async {
      var sends = 0;
      final repo = MemoryRepository();
      final c = await setup(
        repo,
        TwilioApi(
          client: MockClient((_) async {
            sends++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final run = await c.createRun(template(), c.contacts, true, false);
      repo.failOnAttempt = true;
      await expectLater(
        c.process(run, interval: Duration.zero),
        throwsStateError,
      );
      expect(sends, 0);
      expect(c.sending, false);
    },
  );
  test(
    'free-form photos use MediaUrl and delivery refresh keeps API states',
    () async {
      final repo = MemoryRepository();
      final c = await setup(
        repo,
        TwilioApi(
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response('{"status":"delivered"}', 200);
            }
            final fields = Uri.splitQueryString(request.body);
            expect(fields['Body'], 'Hello Ali');
            expect(fields['MediaUrl'], 'https://example.com/photo.jpg');
            return http.Response(
              jsonEncode({'sid': 'SM${'4' * 32}', 'status': 'queued'}),
              201,
            );
          }),
        ),
      );
      final run = await c.createRun(
        Draft()
          ..template = false
          ..body = 'Hello {{name}}'
          ..mediaUrl = 'https://example.com/photo.jpg',
        c.contacts,
        true,
        true,
      );
      await c.process(run, interval: Duration.zero);
      await c.refresh(run);
      expect(run.attempts.values.single.status, 'delivered');
    },
  );
}
