import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_native/controller.dart';
import 'package:relay_native/domain.dart';
import 'package:relay_native/templates.dart';
import 'package:relay_native/template_editor.dart';
import 'package:relay_native/twilio_assets.dart';

import 'helpers.dart';

Settings config() => Settings()
  ..accountSid = 'AC${'1' * 32}'
  ..apiKeySid = 'SK${'2' * 32}'
  ..secret = 'synthetic-secret'
  ..sender = '+9647700000000';
String sid(String prefix) => '$prefix${'3' * 32}';
http.Response json(Object data, [int code = 200]) => http.Response(
  jsonEncode(data),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]);
Map<String, dynamic> sampleTemplate() => {
  'sid': sid('HX'),
  'friendly_name': 'ترحيب',
  'language': 'ar',
  'variables': {'1': 'علي', '2': 'order-10'},
  'types': {
    'twilio/call-to-action': {
      'body': 'مرحباً {{1}}.',
      'actions': [
        {'type': 'URL', 'title': 'الموقع', 'url': 'https://example.com/{{2}}'},
      ],
    },
  },
};

void main() {
  test('Twilio Assets publishes multipart image, preserves old assets, and verifies URL without credentials', () async {
    final s = config();
    var persist = 0, envReads = 0, statusReads = 0;
    bool deployed = false;
    final old = sid('ZB'),
        previous = sid('ZN'),
        fresh = 'ZN${'4' * 32}',
        build = 'ZB${'4' * 32}';
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.url.host.endsWith('.twil.io')) {
        expect(request.method, 'GET');
        expect(request.url.host, 'relay-test-photos.twil.io');
        expect(request.headers.containsKey('Authorization'), false);
        expect(deployed, true);
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }
      expect(request.headers['Authorization'], startsWith('Basic '));
      if (path == '/v1/Services') return json({'sid': sid('ZS')}, 201);
      if (path.endsWith('/Environments')) return json({'sid': sid('ZE')}, 201);
      if (path.endsWith('/Environments/${sid('ZE')}')) {
        envReads++;
        return json({
          'domain_name': 'relay-test-photos.twil.io',
          'build_sid': old,
        });
      }
      if (path.endsWith('/Builds/$old')) {
        return json({
          'asset_versions': [
            {'sid': previous},
          ],
          'function_versions': [],
        });
      }
      if (path.endsWith('/Assets')) return json({'sid': sid('ZH')}, 201);
      if (request.url.host == 'serverless-upload.twilio.com') {
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('name="Content"'));
        expect(body.toLowerCase(), contains('content-type: image/png'));
        expect(body, contains('public'));
        expect(body, contains('/photos/'));
        return json({'sid': fresh}, 201);
      }
      if (path.endsWith('/Builds')) {
        final fields = Uri.splitQueryString(request.body);
        expect(fields['Dependencies'], '[]');
        expect(RegExp('AssetVersions=').allMatches(request.body).length, 2);
        expect(request.body, contains(previous));
        expect(request.body, contains(fresh));
        return json({'sid': build, 'status': 'building'}, 201);
      }
      if (path.endsWith('/Status')) {
        return json({'status': ++statusReads == 1 ? 'building' : 'completed'});
      }
      if (path.endsWith('/Deployments')) {
        deployed = true;
        expect(request.bodyFields['BuildSid'], build);
        return json({'sid': sid('ZD')}, 201);
      }
      fail('Unexpected ${request.method} $path');
    });
    final url = await TwilioAssets(client, pollInterval: Duration.zero).upload(
      s,
      png,
      'a.png',
      persistConfiguration: () async {
        persist++;
      },
    );
    expect(url, startsWith('https://relay-test-photos.twil.io/photos/'));
    expect(persist, 4);
    expect(envReads, 2);
    expect(s.mediaAccountSid, s.accountSid);
  });
  for (final scenario in ['failed build', 'concurrent deployment']) {
    test('Twilio Assets refuses deployment after $scenario', () async {
      final s = config()
        ..mediaServiceSid = sid('ZS')
        ..mediaEnvironmentSid = sid('ZE');
      s.mediaAccountSid = s.accountSid;
      var envReads = 0;
      bool deployed = false;
      final client = MockClient((request) async {
        final p = request.url.path;
        if (p.endsWith('/Environments/${sid('ZE')}')) {
          return json({
            'domain_name': 'test.twil.io',
            'build_sid': ++envReads > 1 ? 'ZB${'5' * 32}' : null,
          });
        }
        if (p.endsWith('/Assets')) return json({'sid': sid('ZH')});
        if (p.endsWith('/Versions')) return json({'sid': sid('ZN')});
        if (p.endsWith('/Builds')) {
          return json({
            'sid': sid('ZB'),
            'status': scenario == 'failed build' ? 'building' : 'completed',
          });
        }
        if (p.endsWith('/Status')) return json({'status': 'failed'});
        if (p.endsWith('/Deployments')) {
          deployed = true;
          return json({});
        }
        fail('Unexpected $p');
      });
      await expectLater(
        TwilioAssets(
          client,
          pollInterval: Duration.zero,
        ).upload(s, png, 'photo.png', persistConfiguration: () async {}),
        throwsA(isA<AssetUploadException>()),
      );
      expect(deployed, false);
    });
  }
  test('bad image is rejected before any Twilio API request', () async {
    var called = false;
    final api = TwilioAssets(
      MockClient((_) async {
        called = true;
        return json({});
      }),
    );
    await expectLater(
      api.upload(
        config(),
        Uint8List.fromList([1, 2, 3]),
        'bad.png',
        persistConfiguration: () async {},
      ),
      throwsA(isA<AssetUploadException>()),
    );
    expect(called, false);
  });
  test('template parser discovers body and URL variables and personalizes the real preview', () {
    final t = WhatsAppTemplate(sampleTemplate());
    expect(t.slots, ['1', '2']);
    expect(t.status, 'unknown');
    expect(
      t.render(t.body, {
        '1': '{{name}}',
      }, Contact(name: 'نور', phone: '+9647700000000')),
      'مرحباً نور.',
    );
    final card = WhatsAppTemplate({
      'types': {
        'twilio/card': {
          'title': 'نص واتساب',
          'media': ['https://example.com/a.png'],
          'actions': [],
        },
      },
    });
    expect(card.body, 'نص واتساب');
    expect(card.media.single, 'https://example.com/a.png');
  });
  test('template list follows valid pagination and independently verifies approval', () async {
    var pages = 0;
    final api = TemplateApi(
      MockClient((request) async {
        if (request.url.path.endsWith('/ApprovalRequests')) {
          return json({
            'whatsapp': {'status': 'approved'},
          });
        }
        pages++;
        return json({
          'contents': pages == 1 ? [sampleTemplate()] : [],
          'meta': {
            'next_page_url': pages == 1
                ? 'https://content.twilio.com/v1/ContentAndApprovals?Page=1'
                : null,
          },
        });
      }),
    );
    final list = await api.list(config());
    expect(pages, 2);
    expect(list.single.status, 'unknown');
    expect((await api.refresh(config(), list.single)).status, 'approved');
  });
  test(
    'pagination refuses foreign hosts before forwarding credentials',
    () async {
      var requests = 0;
      final api = TemplateApi(
        MockClient((_) async {
          requests++;
          return json({
            'contents': [],
            'meta': {'next_page_url': 'https://attacker.example/steal'},
          });
        }),
      );
      await expectLater(api.list(config()), throwsStateError);
      expect(requests, 1);
    },
  );
  test('template creation and approval send correct JSON, with photo plus URL buttons', () async {
    var count = 0;
    final api = TemplateApi(
      MockClient((request) async {
        count++;
        final body = jsonDecode(request.body) as Map;
        if (count == 1) {
          expect(request.url.path, '/v1/Content');
          expect(body['language'], 'ar');
          expect(body['types']['twilio/card']['title'], 'مرحباً {{1}}.');
          expect(body['types']['twilio/card']['media'], [
            'https://example.com/photo.png',
          ]);
          expect(body['types']['twilio/card']['actions'][0], {
            'type': 'URL',
            'title': 'الموقع',
            'url': 'https://example.com',
          });
          return json({...body, 'sid': sid('HX')}, 201);
        }
        expect(
          request.url.path,
          '/v1/Content/${sid('HX')}/ApprovalRequests/whatsapp',
        );
        expect(body, {'name': 'relay_test', 'category': 'MARKETING'});
        return json({'status': 'received'}, 201);
      }),
    );
    final value = await api.create(
      config(),
      name: 'ترحيب',
      language: 'ar',
      body: 'مرحباً {{1}}.',
      samples: {'1': 'علي'},
      links: [
        {'title': 'الموقع', 'url': 'https://example.com'},
      ],
      mediaUrl: 'https://example.com/photo.png',
    );
    expect(value.status, 'unsubmitted');
    expect(
      (await api.submit(config(), value, 'relay_test', 'MARKETING')).status,
      'received',
    );
    expect(count, 2);
  });
  test('template validation catches missing examples, invalid links and excess buttons locally', () async {
    var requests = 0;
    final api = TemplateApi(
      MockClient((_) async {
        requests++;
        return json({});
      }),
    );
    for (final links in [
      [
        {'title': 'الموقع', 'url': 'javascript:alert(1)'},
      ],
      List.generate(3, (_) => {'title': 'site', 'url': 'https://example.com'}),
    ]) {
      await expectLater(
        api.create(
          config(),
          name: 'Test',
          language: 'ar',
          body: 'Hello',
          samples: {},
          links: links,
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      api.create(
        config(),
        name: 'Test',
        language: 'ar',
        body: 'Hello {{1}}.',
        samples: {},
        links: [],
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });
  test(
    'server failure is marked uncertain after a template creation POST',
    () async {
      final api = TemplateApi(
        MockClient((_) async => json({'message': 'error'}, 503)),
      );
      await expectLater(
        api.create(
          config(),
          name: 'Test',
          language: 'en',
          body: 'Hello.',
          samples: {},
          links: [],
        ),
        throwsA(
          isA<ContentFailure>().having((e) => e.uncertain, 'uncertain', true),
        ),
      );
    },
  );
  test('pending template cannot create a send run', () async {
    final c = RelayController(repository: MemoryRepository());
    await c.initialize();
    await c.saveSettings(config());
    final contact = Contact(
      name: 'Ali',
      phone: '+9647701234567',
      consent: true,
    );
    await c.addContacts([contact]);
    final d = Draft()
      ..contentSid = sid('HX')
      ..variables = '{"1":"Ali","2":"abc"}'
      ..templateData = {...sampleTemplate(), 'relay_status': 'pending'};
    await expectLater(c.createRun(d, [contact], true, false), throwsStateError);
    expect(c.runs, isEmpty);
  });
  testWidgets('beginner template fields update preview values without JSON', (
    tester,
  ) async {
    final c = RelayController(repository: MemoryRepository());
    await c.initialize();
    c.settings = config();
    c.draft.templateData = {...sampleTemplate(), 'relay_status': 'approved'};
    c.draft.contentSid = sid('HX');
    c.draft.variables = '{"1":"Ali","2":"abc"}';
    Map<String, String> changed = {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TemplatePanel(
              c: c,
              onSelected: (_, _) {},
              onValues: (values) => changed = values,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('template-value-1')),
      'نور',
    );
    expect(changed['1'], 'نور');
    await tester.tap(find.text('اسم كل مستلم').first);
    await tester.pump();
    expect(changed['1'], '{{name}}');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'phone template wizard can add and remove two URL buttons without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = RelayController(repository: MemoryRepository());
      await c.initialize();
      c.settings = config();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => TemplateDialog(c: c),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final add = find.text('إضافة زر رابط');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('button-label-0')));
      await tester.enterText(
        find.byKey(const ValueKey('button-label-0')),
        'زيارة الموقع',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('button-url-0')));
      await tester.enterText(
        find.byKey(const ValueKey('button-url-0')),
        'https://example.com',
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('button-label-1')), findsOneWidget);
      expect(add, findsNothing);
      await tester.ensureVisible(find.text('إزالة الزر').first);
      await tester.tap(find.text('إزالة الزر').first);
      await tester.pumpAndSettle();
      expect(find.text('إضافة زر رابط'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
