import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relay_native/controller.dart';
import 'package:relay_native/domain.dart';
import 'package:relay_native/main.dart';
import 'package:relay_native/services.dart';
import 'package:relay_native/photo_recovery.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/helpers.dart';

class IsolatedPaths extends PathProviderPlatform {
  IsolatedPaths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native secure storage and contact persistence survive reopening', (
    tester,
  ) async {
    final root = Directory(
      '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}relay-smoke-${newId()}',
    ).absolute;
    final key = 'relay.smoke.${newId()}';
    await root.create(recursive: true);
    // Keep the test's encrypted vault inside the writable test sandbox.
    // The real native secure-storage implementation still performs encryption.
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = IsolatedPaths(root.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
    });
    final repo = DeviceRepository(directory: root, credentialsKey: key);
    var controller = RelayController(repository: repo);
    await controller.initialize();
    expect(controller.error, isNull);
    expect(controller.ready, true);
    final settings = Settings()
      ..brand = 'Relay native test'
      ..secret = 'synthetic-test-secret';
    await controller.saveSettings(settings);
    await controller.addContacts([
      Contact(name: 'Native test', phone: '+9647701234567'),
    ]);
    await tester.pumpWidget(RelayApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('رسالة جديدة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('رسالة جديدة'))),
      TextDirection.rtl,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    controller.dispose();
    await repo.close();
    final reopened = DeviceRepository(directory: root, credentialsKey: key);
    controller = RelayController(repository: reopened);
    await controller.initialize();
    expect(controller.settings.secret, 'synthetic-test-secret');
    expect(controller.contacts.single.name, 'Native test');
    final saved = await File('${root.path}/Relay/state.json').readAsString();
    expect(saved.contains('synthetic-test-secret'), false);
    await reopened.vault.delete(key: key);
    await reopened.close();
    controller.dispose();
    final expectedPrefix =
        '${Directory.current.absolute.path}${Platform.pathSeparator}build${Platform.pathSeparator}relay-smoke-';
    if (!root.path.startsWith(expectedPrefix)) {
      throw StateError('Unsafe cleanup path');
    }
    await root.delete(recursive: true);
  });
  testWidgets(
    'native recovery reads the saved public photo and applies it without reuploading',
    (tester) async {
      const url = 'https://relay-native-test.twil.io/photo.png';
      var requests = 0;
      String? applied;
      final controller = RelayController(
        repository: MemoryRepository(),
        api: TwilioApi(
          client: MockClient((request) async {
            requests++;
            expect(request.method, 'GET');
            expect(request.headers.containsKey('Authorization'), false);
            return http.Response.bytes(
              Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        ),
      );
      await controller.initialize();
      controller.settings.language = 'en';
      controller.settings.lastPhotoUrl = url;
      controller.settings.lastPhotoPending = true;
      controller.settings.lastPhotoError = 'HTTP 404';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotoRecovery(
                c: controller,
                onVerified: (value) => applied = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(url), findsOneWidget);
      await tester.tap(find.text('Retry check & use photo'));
      await tester.pumpAndSettle();
      expect(applied, url);
      expect(requests, 1);
      expect(controller.settings.lastPhotoPending, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.api.client.close();
      controller.dispose();
    },
  );
}
