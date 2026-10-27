import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_native/controller.dart';
import 'package:relay_native/main.dart';

import 'helpers.dart';

void main() {
  testWidgets(
    'native app starts in Arabic RTL, switches screens, opens dialog and switches language',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = RelayController(repository: MemoryRepository());
      await c.initialize();
      await tester.pumpWidget(RelayApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('رسالة جديدة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('رسالة جديدة'))),
        TextDirection.rtl,
      );
      await tester.tap(find.text('جهات الاتصال'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة جهة'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), 'Ali');
      await tester.enterText(dialogFields.at(1), '07701234567');
      await tester.tap(find.widgetWithText(FilledButton, 'إضافة'));
      await tester.pumpAndSettle();
      expect(c.contacts.single.phone, '+9647701234567');
      expect(c.contacts.single.consent, false);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(c.settings.language, 'en');
      expect(find.text('Add contact'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'phone layout has usable navigation with no overflow in either language',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = RelayController(repository: MemoryRepository());
      await c.initialize();
      await tester.pumpWidget(RelayApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final name in ['جهات الاتصال', 'سجل الإرسال', 'الإعدادات']) {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
