import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_native/controller.dart';
import 'package:relay_native/domain.dart';
import 'package:relay_native/photo_probe.dart';
import 'package:relay_native/photo_recovery.dart';
import 'package:relay_native/services.dart';
import 'package:relay_native/twilio_assets.dart';

import 'helpers.dart';

final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]);
const url = 'https://relay-photos.twil.io/photos/a.png';
Settings config() => Settings()
  ..language = 'en'
  ..accountSid = 'AC${'1' * 32}'
  ..apiKeySid = 'SK${'2' * 32}'
  ..secret = 'test-only'
  ..sender = '+9647700000000';
String sid(String prefix) => '$prefix${'3' * 32}';
http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
PublicPhotoProbe probe(http.Client client) =>
    PublicPhotoProbe(client, attempts: 3, interval: Duration.zero);

void main() {
  test('a working GET succeeds without HEAD or authorization, even when HEAD is unsupported', () async {
    var head = 0, get = 0;
    final client = MockClient((r) async {
      expect(r.headers.containsKey('Authorization'), false);
      if (r.method == 'HEAD') {
        head++;
        return http.Response('', 405);
      }
      get++;
      return http.Response.bytes(
        png,
        200,
        headers: {'content-type': 'image/png; charset=binary'},
      );
    });
    expect(await probe(client).verify(url), url);
    expect(head, 0);
    expect(get, 1);
  });
  test('propagation retries a 404 then verifies actual image bytes', () async {
    var calls = 0;
    final client = MockClient(
      (_) async => ++calls == 1
          ? http.Response('Not ready', 404)
          : http.Response.bytes(
              png,
              200,
              headers: {'content-type': 'image/png'},
            ),
    );
    expect(await probe(client).verify(url), url);
    expect(calls, 2);
  });
  for (final response in [
    http.Response(
      '<html>error</html>',
      200,
      headers: {'content-type': 'text/html'},
    ),
    http.Response(
      '<html>error</html>',
      200,
      headers: {'content-type': 'image/png'},
    ),
    http.Response.bytes(
      png,
      200,
      headers: {'content-type': 'application/octet-stream'},
    ),
    http.Response('Denied', 403),
  ]) {
    test(
      'invalid public image response is diagnosed: ${response.statusCode} ${response.headers['content-type']}',
      () async {
        await expectLater(
          probe(MockClient((_) async => response)).verify(url),
          throwsA(
            isA<PhotoCheckFailure>()
                .having((e) => e.url, 'retained URL', url)
                .having(
                  (e) => e.detail,
                  'HTTP status',
                  contains('HTTP ${response.statusCode}'),
                ),
          ),
        );
      },
    );
  }
  test('DNS failure and timeout remain distinguishable', () async {
    for (final error in [
      const SocketException('private detail'),
      TimeoutException('private detail'),
    ]) {
      await expectLater(
        probe(MockClient((_) async => throw error)).verify(url),
        throwsA(
          isA<PhotoCheckFailure>()
              .having(
                (e) => e.detail,
                'failure type',
                contains(error is SocketException ? 'DNS' : 'timed out'),
              )
              .having(
                (e) => e.detail,
                'no raw exception data',
                isNot(contains('private detail')),
              ),
        ),
      );
    }
  });
  test(
    'redirects are checked without credentials, with no HTTPS downgrade',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        expect(r.headers.containsKey('Authorization'), false);
        if (r.url.path == '/photos/a.png') {
          return http.Response('', 302, headers: {'location': '/cdn/a.png'});
        }
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      expect(await probe(client).verify(url), url);
      expect(calls, 2);
      var attempts = 0;
      await expectLater(
        PublicPhotoProbe(
          MockClient((_) async {
            attempts++;
            return http.Response(
              '',
              302,
              headers: {'location': 'http://localhost/a.png'},
            );
          }),
          attempts: 1,
        ).verify(url),
        throwsA(isA<PhotoCheckFailure>()),
      );
      expect(attempts, 1);
    },
  );
  test('failed public check retains the deployed URL across restart and recheck never uploads', () async {
    final repo = MemoryRepository();
    final client = MockClient((r) async {
      final p = r.url.path;
      if (r.url.host.endsWith('.twil.io')) {
        return http.Response('Not ready', 404);
      }
      if (p.endsWith('/Environments/${sid('ZE')}')) {
        return json({'domain_name': 'relay-photos.twil.io', 'build_sid': null});
      }
      if (p.endsWith('/Assets')) return json({'sid': sid('ZH')});
      if (p.endsWith('/Versions')) return json({'sid': sid('ZN')});
      if (p.endsWith('/Builds')) {
        return json({'sid': sid('ZB'), 'status': 'completed'});
      }
      if (p.endsWith('/Deployments')) return json({'sid': sid('ZD')});
      fail('Unexpected request: $p');
    });
    final c = RelayController(
      repository: repo,
      api: SingleAttemptAssets(client),
    );
    await c.initialize();
    final settings = config()
      ..mediaServiceSid = sid('ZS')
      ..mediaEnvironmentSid = sid('ZE');
    settings.mediaAccountSid = settings.accountSid;
    await c.saveSettings(settings);
    await expectLater(
      c.uploadPhoto(png, 'photo.png'),
      throwsA(isA<PhotoCheckFailure>()),
    );
    expect(
      c.settings.lastPhotoUrl,
      startsWith('https://relay-photos.twil.io/photos/'),
    );
    expect(c.settings.lastPhotoPending, true);
    expect(c.settings.lastPhotoError, contains('HTTP 404'));
    expect(c.mediaBusy, false);
    var gets = 0;
    final reopened = RelayController(
      repository: repo,
      api: TwilioApi(
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.headers.containsKey('Authorization'), false);
          gets++;
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await reopened.initialize();
    expect(reopened.settings.lastPhotoPending, true);
    final retained = reopened.settings.lastPhotoUrl;
    expect(await reopened.retryPhotoCheck(), retained);
    expect(gets, 1);
    expect(reopened.settings.lastPhotoPending, false);
    expect(reopened.settings.lastPhotoError, '');
    expect(repo.state['settings']['lastPhotoPending'], false);
  });
  testWidgets(
    'phone recovery displays the retained link and retries without creating another upload',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? used;
      final api = ImmediatePhotoApi();
      final c = RelayController(repository: MemoryRepository(), api: api);
      await c.initialize();
      c.settings = config()
        ..lastPhotoPending = true
        ..lastPhotoUrl = url
        ..lastPhotoError = 'HTTP 404';
      c.settings.mediaAccountSid = c.settings.accountSid;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotoRecovery(
                c: c,
                onVerified: (value) {
                  used = value;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(url), findsOneWidget);
      expect(find.text('HTTP 404'), findsOneWidget);
      await tester.tap(find.text('Retry check & use photo'));
      await tester.pumpAndSettle();
      expect(used, url);
      expect(api.checks, 1);
      expect(find.text(url), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class ImmediatePhotoApi extends TwilioApi {
  int checks = 0;
  @override
  Future<String> verifyPhoto(
    Settings s,
    String url, {
    void Function(String)? onProgress,
  }) async {
    checks++;
    return url;
  }
}

class SingleAttemptAssets extends TwilioApi {
  SingleAttemptAssets(http.Client client) : super(client: client);
  @override
  Future<String> upload(
    Settings s,
    Uint8List bytes,
    String name, {
    required Future<void> Function() persistConfiguration,
    void Function(String)? onProgress,
  }) =>
      TwilioAssets(
        client,
        pollInterval: Duration.zero,
        publicCheckAttempts: 1,
      ).upload(
        s,
        bytes,
        name,
        persistConfiguration: persistConfiguration,
        onProgress: onProgress,
      );
}
