import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'domain.dart';
import 'services.dart';
import 'templates.dart';
import 'template_editor.dart';
import 'photo_recovery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = RelayController(repository: DeviceRepository());
  await controller.initialize();
  runApp(RelayApp(controller: controller));
}

void notice(BuildContext context, Object message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$message'),
      showCloseIcon: true,
      duration: const Duration(seconds: 6),
    ),
  );
}

Future<void> protect(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) notice(context, e);
  }
}

Future<void> exportCsv(
  BuildContext context,
  String name,
  List<List<Object?>> rows,
) async {
  await FilePicker.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: utf8.encode(csvFile(rows)),
  );
}

class RelayApp extends StatelessWidget {
  const RelayApp({super.key, required this.controller});
  final RelayController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Relay',
      locale: Locale(controller.settings.language),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff17634c),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f7f6),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 17, height: 1.65),
          bodyMedium: TextStyle(fontSize: 16, height: 1.65),
          bodySmall: TextStyle(fontSize: 14, height: 1.6),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(7)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          filled: true,
          fillColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: const BorderSide(color: Color(0xffdfe7e1)),
          ),
        ),
        dividerColor: const Color(0xffdfe7e1),
      ),
      home: controller.ready
          ? Studio(controller: controller)
          : Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 48),
                        const SizedBox(height: 20),
                        const Text(
                          'تعذر فتح التخزين الآمن / Unable to open local storage',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          controller.error ?? '',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'أغلق أي نسخة أخرى من Relay ثم أعد فتح التطبيق.\nClose other Relay instances and restart.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

class Studio extends StatefulWidget {
  const Studio({super.key, required this.controller});
  final RelayController controller;
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  int page = 0;
  RelayController get c => widget.controller;
  @override
  Widget build(BuildContext context) {
    final labels = [
      c.t('إنشاء رسالة', 'Compose'),
      c.t('جهات الاتصال', 'Contacts'),
      c.t('سجل الإرسال', 'Activity'),
      c.t('الإعدادات', 'Settings'),
    ];
    const icons = [
      Icons.edit_outlined,
      Icons.people_outline,
      Icons.history,
      Icons.settings_outlined,
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Relay · ${labels[page]}',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => protect(
              context,
              () => c.setLanguage(c.settings.language == 'ar' ? 'en' : 'ar'),
            ),
            icon: const Icon(Icons.language, size: 20),
            label: Text(c.settings.language == 'ar' ? 'English' : 'العربية'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width > 1150,
              minExtendedWidth: 225,
              backgroundColor: Colors.white,
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Relay',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff17634c),
                  ),
                ),
              ),
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(labels[i]),
                  ),
              ],
            ),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: page,
              children: [
                ComposePage(
                  c: c,
                  settings: () => setState(() => page = 3),
                  activity: () => setState(() => page = 2),
                ),
                ContactsPage(c: c),
                ActivityPage(c: c),
                SettingsPage(c: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 32),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 25),
            ...children,
            const SizedBox(height: 30),
          ],
        ),
      ),
    ),
  );
}

class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 25,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget hint(String s) => Padding(
  padding: const EdgeInsets.only(top: 9, bottom: 17),
  child: Text(
    s,
    style: const TextStyle(fontSize: 14, color: Color(0xff63766a), height: 1.8),
  ),
);
Widget gap() => const SizedBox(height: 18);

class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    required this.c,
    required this.settings,
    required this.activity,
  });
  final RelayController c;
  final VoidCallback settings, activity;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  RelayController get c => widget.c;
  late final name = TextEditingController(text: c.draft.name),
      body = TextEditingController(text: c.draft.body),
      sid = TextEditingController(text: c.draft.contentSid),
      variables = TextEditingController(text: c.draft.variables),
      media = TextEditingController(text: c.draft.mediaUrl);
  String uploadProgress = '';
  bool consent = false, window = false, uploading = false, reviewing = false;
  bool get template => c.draft.template;
  @override
  void dispose() {
    for (final t in [name, body, sid, variables, media]) {
      t.dispose();
    }
    super.dispose();
  }

  Draft collect() => c.draft
    ..name = name.text
    ..body = body.text
    ..contentSid = sid.text.trim()
    ..variables = variables.text
    ..mediaUrl = template ? '' : media.text.trim();
  Future<void> upload() async {
    if (!c.settings.canUpload) {
      throw StateError(
        c.t(
          'احفظ بيانات Twilio في الإعدادات أولاً',
          'Save Twilio credentials in Settings first.',
        ),
      );
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final size = await file.length();
    if (size != null && size > 5 * 1024 * 1024) {
      throw StateError('5 MB maximum');
    }
    setState(() => uploading = true);
    try {
      final url = await c.uploadPhoto(
        await file.readAsBytes(),
        file.name,
        onProgress: (value) {
          if (mounted) setState(() => uploadProgress = value);
        },
      );
      if (mounted) setState(() => media.text = url);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> review() async {
    if (reviewing || c.sending || c.mediaBusy) return;
    setState(() => reviewing = true);
    try {
      await reviewInner();
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
  }

  Future<void> reviewInner() async {
    if (template && c.draft.templateData.isNotEmpty) {
      final value = await TemplateApi(c.api.client)
          .refresh(c.settings, WhatsAppTemplate(c.draft.templateData));
      if (!mounted) return;
      setState(() => c.draft.templateData = value.toJson());
    }
    final d = collect().copy(),
        audience = c.contacts.where((v) => v.selected).toList();
    c.validateDraft(d, audience, consent, window);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.t('تأكيد الإرسال الحقيقي', 'Confirm real sending')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${audience.length} ${c.t('مستلم', 'recipients')}'),
              gap(),
              Text(
                '${c.t('المرسل', 'Sender')}: ${c.settings.sender}',
                textDirection: TextDirection.ltr,
              ),
              gap(),
              Text(
                c.t(
                  'سيستخدم هذا رصيد حساب Twilio. ابدأ برسالة إلى أول جهة فقط للتأكد من الإعداد.',
                  'This uses your Twilio balance. Start with the first contact to verify setup.',
                ),
              ),
              gap(),
              Text(
                '${c.t('أول جهة', 'First contact')}: ${audience.first.name} (${audience.first.phone})',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(c.t('إلغاء', 'Cancel')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'first'),
            child: Text(c.t('الأولى فقط', 'First only')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: Text(c.t('إرسال للجميع', 'Send to all')),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final run = await c.createRun(
      d,
      choice == 'first' ? audience.take(1).toList() : audience,
      consent,
      window,
    );
    widget.activity();
    await c.process(run);
    if (mounted) {
      notice(
        context,
        c.t(
          'راجع سجل الإرسال وحدّث الحالات للتحقق من التسليم.',
          'Check Activity and refresh statuses to verify delivery.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = c.contacts.where((v) => v.selected).toList();
    final preview =
        selected.firstOrNull ??
        Contact(name: c.t('عميلنا', 'there'), phone: '+964…');
    return PageBody(
      title: c.t('رسالة جديدة', 'New message'),
      subtitle: c.t(
        'أرسل من جهازك مباشرة عبر Twilio.',
        'Send directly from this device through Twilio.',
      ),
      children: [
        if (!c.settings.connected)
          Section(
            title: c.t('اربط حساب Twilio أولاً', 'Connect Twilio first'),
            children: [
              Text(
                c.t(
                  'أدخل رقم واتساب المعتمد وبيانات API في الإعدادات. لا حاجة لخادم خاص.',
                  'Enter your approved WhatsApp sender and API credentials in Settings. No custom server is needed.',
                ),
              ),
              gap(),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: widget.settings,
                  icon: const Icon(Icons.link),
                  label: Text(c.t('فتح الإعدادات', 'Open Settings')),
                ),
              ),
            ],
          ),
        Section(
          title: c.t('1. المستلمون', '1. Recipients'),
          children: [
            Text(
              '${selected.length} ${c.t('محدد', 'selected')} · ${selected.where((v) => v.consent).length} ${c.t('مع موافقة', 'with consent')}',
            ),
            hint(
              c.t(
                'أضف المستلمين أو استورد ملفاً من صفحة جهات الاتصال، ثم حدد من تريد مراسلته.',
                'Add or import people in Contacts, then select your audience.',
              ),
            ),
          ],
        ),
        Section(
          title: c.t('2. محتوى الرسالة', '2. Message content'),
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: c.t(
                  'اسم الإرسال (للمرجع)',
                  'Send name (for your reference)',
                ),
              ),
            ),
            gap(),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: Text(c.t('قالب معتمد', 'Template')),
                  selected: template,
                  onSelected: (_) => setState(() => c.draft.template = true),
                ),
                ChoiceChip(
                  label: Text(c.t('رد 24 ساعة', '24h reply')),
                  selected: !template,
                  onSelected: (_) => setState(() => c.draft.template = false),
                ),
              ],
            ),
            gap(),
            if (template) ...[
              TemplatePanel(
                c: c,
                onSelected: (value, values) => setState(() {
                  c.draft.templateData = value.toJson();
                  sid.text = value.sid;
                  body.text = value.body;
                  variables.text = jsonEncode(values);
                  collect();
                }),
                onValues: (values) => setState(() {
                  variables.text = jsonEncode(values);
                  collect();
                }),
              ),
              ExpansionTile(
                title: Text(c.t('إعداد يدوي متقدم', 'Advanced manual setup')),
                children: [
                  TextField(
                    controller: sid,
                    textDirection: TextDirection.ltr,
                    onChanged: (_) => setState(() => c.draft.templateData = {}),
                    decoration: const InputDecoration(
                      labelText: 'Content SID',
                      hintText: 'HX…',
                    ),
                  ),
                  gap(),
                  TextField(
                    controller: variables,
                    textDirection: TextDirection.ltr,
                    maxLines: 4,
                    minLines: 2,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: c.t('المتغيرات JSON', 'Variables JSON'),
                    ),
                  ),
                  hint(
                    c.t(
                      'للقوالب المعتمدة فقط. استخدم {} إذا لم توجد متغيرات.',
                      'Approved templates only. Use {} if there are no variables.',
                    ),
                  ),
                ],
              ),
              gap(),
            ],
            TextField(
              controller: body,
              readOnly: template && c.draft.templateData.isNotEmpty,
              minLines: 5,
              maxLines: 10,
              maxLength: 1600,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: c.t(
                  template ? 'نص معاينة القالب (اختياري)' : 'نص الرسالة',
                  template
                      ? 'Template preview text (optional)'
                      : 'Message text',
                ),
                hintText: c.t('مرحباً {{name}}،', 'Hello {{name}},'),
              ),
            ),
            if (!template)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() {
                    final p = body.selection.isValid
                        ? body.selection.start
                        : body.text.length;
                    body.text = body.text.replaceRange(p, p, '{{name}}');
                  }),
                  child: const Text('+ {{name}}'),
                ),
              ),
            if (!template) ...[
              gap(),
              PhotoRecovery(
                c: c,
                onVerified: (url) => setState(() => media.text = url),
              ),
              TextField(
                controller: media,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: c.t(
                    'رابط صورة HTTPS عام (اختياري)',
                    'Public HTTPS photo URL (optional)',
                  ),
                  hintText: 'https://…/photo.jpg',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => media.clear()),
                    icon: const Icon(Icons.close),
                    tooltip: c.t('إزالة', 'Remove'),
                  ),
                ),
              ),
              hint(
                c.t(
                  'يستخدم الرفع حساب Twilio نفسه. تجهيز الرابط قد يستغرق دقيقة أو أكثر. الصور عامة لمن لديه الرابط وتبقى حتى تحذفها من Twilio.',
                  'Uploads use your Twilio account. Preparing the link may take a minute or more. Images are public to anyone with the URL and remain until deleted in Twilio.',
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: uploading || c.mediaBusy || c.sending
                      ? null
                      : () => protect(context, upload),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    uploading
                        ? (uploadProgress.isEmpty
                              ? c.t('جارٍ الرفع…', 'Uploading…')
                              : uploadProgress)
                        : c.t('رفع صورة JPG / PNG', 'Upload JPG / PNG'),
                  ),
                ),
              ),
            ],
          ],
        ),
        Section(
          title: c.t('معاينة الرسالة', 'Message preview'),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xffe9f2e6),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!template && isPublicHttps(media.text)) ...[
                    Image.network(
                      media.text.trim(),
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        c.t(
                          'تعذر عرض الصورة. تحقق من الرابط.',
                          'Unable to display image. Check the URL.',
                        ),
                      ),
                    ),
                    gap(),
                  ],
                  if (template && c.draft.templateData.isNotEmpty)
                    TemplatePhotos(
                      value: WhatsAppTemplate(c.draft.templateData),
                      values: safeVariables(variables.text),
                      contact: preview,
                    ),
                  Text(
                    template && c.draft.templateData.isNotEmpty
                        ? WhatsAppTemplate(c.draft.templateData).render(
                            body.text,
                            safeVariables(variables.text),
                            preview,
                          )
                        : personal(
                            body.text.isNotEmpty
                                ? body.text
                                : c.t(
                                    'اكتب رسالتك لتظهر المعاينة هنا.',
                                    'Write a message to preview it here.',
                                  ),
                            preview,
                          ),
                  ),
                  if (template && c.draft.templateData.isNotEmpty)
                    TemplateLinks(
                      value: WhatsAppTemplate(c.draft.templateData),
                      values: safeVariables(variables.text),
                      contact: preview,
                    ),
                ],
              ),
            ),
            hint(
              c.t(
                'المعاينة تقريبية وتستخدم أول جهة محددة.',
                'Approximate preview using your first selected contact.',
              ),
            ),
          ],
        ),
        Section(
          title: c.t('3. مراجعة وإرسال', '3. Review and send'),
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              title: Text(
                c.t(
                  'أؤكد موافقة كل مستلم على تلقي رسائل واتساب من نشاطي.',
                  'Every recipient opted in to receive WhatsApp messages from my business.',
                ),
              ),
            ),
            if (!template)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: window,
                onChanged: (v) => setState(() => window = v ?? false),
                title: Text(
                  c.t(
                    'كل مستلم راسل نشاطي خلال آخر 24 ساعة.',
                    'Every recipient messaged my business within the past 24 hours.',
                  ),
                ),
              ),
            hint(
              c.t(
                'أبقِ التطبيق مفتوحاً وفي المقدمة أثناء الإرسال. افحص التسليم من سجل الإرسال. الإرسال يُحتسب على رصيد Twilio.',
                'Keep the app open and in the foreground while sending. Check delivery in Activity. Twilio charges apply.',
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: c.sending || c.mediaBusy || reviewing
                      ? null
                      : () => protect(context, review),
                  icon: const Icon(Icons.send_outlined),
                  label: Text(c.t('مراجعة وإرسال', 'Review & send')),
                ),
                OutlinedButton.icon(
                  onPressed: () => protect(context, () async {
                    collect();
                    await c.save();
                    if (context.mounted) {
                      notice(context, c.t('حُفظت المسودة', 'Draft saved'));
                    }
                  }),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(c.t('حفظ المسودة', 'Save draft')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.c});
  final RelayController c;
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  RelayController get c => widget.c;
  String query = '';
  bool importing = false;
  Future<void> add() async {
    final result = await showDialog<Contact>(
      context: context,
      builder: (_) => AddContactDialog(c: c),
    );
    if (result != null) await c.addContacts([result]);
  }

  Future<void> import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (file == null) return;
    final size = await file.length();
    if (size != null && size > 10 * 1024 * 1024) {
      throw StateError('10 MB maximum');
    }
    setState(() => importing = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw StateError('10 MB maximum');
      final book = await readWorkbook(
        bytes,
        file.name.split('.').last.toLowerCase(),
      );
      if (!mounted) return;
      final result = await showDialog<List<Contact>>(
        context: context,
        builder: (_) => ImportDialog(c: c, book: book),
      );
      if (result != null) {
        await c.addContacts(result);
        if (mounted) {
          notice(context, '${c.t('تم استيراد', 'Imported')} ${result.length}');
        }
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> remove(Contact contact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.t('حذف جهة الاتصال؟', 'Delete contact?')),
        content: Text(
          '${contact.name}\n${contact.phone}\n${c.t('يبقى سجل الإرسال محفوظاً.', 'Sending history is retained.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(c.t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(c.t('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) await c.deleteContact(contact);
  }

  @override
  Widget build(BuildContext context) {
    final shown = c.contacts
        .where(
          (v) => '${v.name} ${v.phone}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return PageBody(
      title: c.t('جهات الاتصال', 'Contacts'),
      subtitle:
          '${c.contacts.length} ${c.t('جهة اتصال محفوظة على هذا الجهاز', 'contacts stored on this device')}',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => protect(context, add),
              icon: const Icon(Icons.person_add_alt),
              label: Text(c.t('إضافة جهة', 'Add contact')),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => protect(context, import),
              icon: const Icon(Icons.upload_file),
              label: Text(
                importing
                    ? c.t('جارٍ الاستيراد…', 'Importing…')
                    : c.t('استيراد CSV / Excel', 'Import CSV / Excel'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => protect(
                context,
                () => exportCsv(context, 'relay-contacts.csv', [
                  ['name', 'phone', 'consent'],
                  ...c.contacts.map(
                    (v) => [v.name, v.phone, v.consent ? 'yes' : 'no'],
                  ),
                ]),
              ),
              icon: const Icon(Icons.download_outlined),
              label: Text(c.t('تصدير', 'Export')),
            ),
          ],
        ),
        gap(),
        hint(
          c.t(
            'يدعم CSV وXLSX وXLS (Excel 97–2003). اجعل أرقام Excel نصوصاً للحفاظ على الأصفار. الموافقة غير المسجلة تمنع الإرسال.',
            'Supports CSV, XLSX and XLS (Excel 97–2003). Format phone cells as text to preserve digits. Missing consent blocks sending.',
          ),
        ),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: c.t('ابحث بالاسم أو الرقم', 'Search name or phone'),
          ),
        ),
        gap(),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            TextButton(
              onPressed: () =>
                  protect(context, () => c.selectContacts(shown, true)),
              child: Text(c.t('تحديد النتائج', 'Select results')),
            ),
            TextButton(
              onPressed: () =>
                  protect(context, () => c.selectContacts(shown, false)),
              child: Text(c.t('إلغاء التحديد', 'Deselect results')),
            ),
            TextButton(
              onPressed: () => protect(
                context,
                () => exportCsv(context, 'relay-sample.csv', [
                  ['name', 'phone', 'consent'],
                  ['عميل تجريبي', '07701234567', 'no'],
                ]),
              ),
              child: Text(c.t('تنزيل نموذج CSV', 'Download CSV sample')),
            ),
          ],
        ),
        gap(),
        if (shown.isEmpty)
          Section(
            title: c.t('لا توجد جهات اتصال', 'No contacts found'),
            children: [
              Text(
                c.t(
                  'أضف جهة أو استورد جدولاً للبدء.',
                  'Add a person or import a spreadsheet to get started.',
                ),
              ),
            ],
          ),
        ...shown.map(
          (v) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: v.selected,
                          onChanged: (value) => protect(
                            context,
                            () => c.changeContact(v, selected: value),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.name.isEmpty ? '—' : v.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(v.phone, textDirection: TextDirection.ltr),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => protect(context, () => remove(v)),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: c.t('حذف', 'Delete'),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      dense: true,
                      value: v.consent,
                      onChanged: (value) => protect(
                        context,
                        () => c.changeContact(v, consent: value),
                      ),
                      title: Text(
                        c.t('موافقة واتساب مسجلة', 'WhatsApp consent recorded'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({super.key, required this.c, required this.book});
  final RelayController c;
  final Map<String, List<List<String>>> book;
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class AddContactDialog extends StatefulWidget {
  const AddContactDialog({super.key, required this.c});
  final RelayController c;
  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  final name = TextEditingController(), phone = TextEditingController();
  bool consent = false;
  String? error;
  RelayController get c => widget.c;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(c.t('إضافة جهة اتصال', 'Add contact')),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: c.t('الاسم', 'Name')),
            ),
            gap(),
            TextField(
              controller: phone,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: c.t('رقم الهاتف', 'Phone number'),
                hintText: '0770 123 4567',
                errorText: error,
              ),
            ),
            hint(
              '${c.t('رمز الدولة الافتراضي', 'Default country code')}: +${c.settings.countryCode}',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              title: Text(
                c.t(
                  'هذه الجهة وافقت على تلقي رسائل واتساب مني.',
                  'This person consented to my WhatsApp messages.',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(c.t('إلغاء', 'Cancel')),
      ),
      FilledButton(
        onPressed: () {
          final number = normalizePhone(phone.text, c.settings.countryCode);
          if (number == null || c.contacts.any((v) => v.phone == number)) {
            setState(
              () => error = c.t(
                'رقم غير صالح أو موجود بالفعل',
                'Invalid or duplicate phone',
              ),
            );
            return;
          }
          Navigator.pop(
            context,
            Contact(name: name.text.trim(), phone: number, consent: consent),
          );
        },
        child: Text(c.t('إضافة', 'Add')),
      ),
    ],
  );
}

class _ImportDialogState extends State<ImportDialog> {
  RelayController get c => widget.c;
  late String sheet = widget.book.keys.first;
  int phone = 0, name = -1, consent = -1;
  bool allConsent = false;
  List<List<String>> get rows => widget.book[sheet]!;
  @override
  void initState() {
    super.initState();
    guess();
  }

  void guess() {
    final headers = rows.first;
    int find(String regex) => headers.indexWhere(
      (h) => RegExp(regex, caseSensitive: false).hasMatch(h),
    );
    phone = find('phone|mobile|whatsapp|هاتف|رقم|موبايل');
    if (phone < 0) phone = 0;
    name = find('name|اسم');
    consent = find('consent|opt.?in|موافقة');
  }

  Widget column(
    String label,
    int value,
    void Function(int) change, {
    bool optional = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$label$sheet$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional)
          DropdownMenuItem(value: -1, child: Text(c.t('بدون', 'None'))),
        for (var i = 0; i < rows.first.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              rows.first[i].isEmpty ? '${i + 1}' : rows.first[i],
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() => change(v!)),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final result = mapContacts(
      rows,
      phone,
      name,
      consent,
      c.settings.countryCode,
      c.contacts,
      allConsent: allConsent,
    );
    return AlertDialog(
      title: Text(c.t('مطابقة أعمدة الملف', 'Match file columns')),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.t(
                  'يجب أن يحتوي الصف الأول على عناوين الأعمدة.',
                  'Your first row must contain column headers.',
                ),
              ),
              gap(),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: sheet,
                decoration: InputDecoration(
                  labelText: c.t('الورقة', 'Worksheet'),
                ),
                items: widget.book.keys
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() {
                  sheet = v!;
                  guess();
                }),
              ),
              gap(),
              column(
                c.t('عمود الهاتف', 'Phone column'),
                phone,
                (v) => phone = v,
                optional: false,
              ),
              column(c.t('عمود الاسم', 'Name column'), name, (v) => name = v),
              column(
                c.t('عمود الموافقة', 'Consent column'),
                consent,
                (v) => consent = v,
              ),
              hint(
                c.t(
                  'الموافقة تُقرأ من yes / true / 1 / نعم. غير ذلك يعني عدم تسجيل الموافقة.',
                  'Consent recognizes yes / true / 1 / نعم. Other values mean no recorded consent.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: allConsent,
                onChanged: (v) => setState(() => allConsent = v ?? false),
                title: Text(
                  c.t(
                    'أؤكد أن جميع جهات هذا الملف وافقت فعلياً على تلقي رسائلي.',
                    'I confirm every contact in this file actually opted in.',
                  ),
                ),
              ),
              gap(),
              Text(
                '${result.contacts.length} ${c.t('صالح', 'valid')} · ${result.duplicates} ${c.t('مكرر', 'duplicates')} · ${result.invalidRows.length} ${c.t('غير صالح', 'invalid')}',
              ),
              if (result.invalidRows.isNotEmpty)
                hint(
                  '${c.t('صفوف مستبعدة', 'Rejected rows')}: ${result.invalidRows.take(15).join(', ')}',
                ),
              const Divider(),
              ...result.contacts
                  .take(4)
                  .map(
                    (v) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${v.name} · ${v.phone}\n${v.consent ? c.t('مع موافقة', 'Consent recorded') : c.t('بدون موافقة', 'No consent')}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.t('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: result.contacts.isEmpty
              ? null
              : () => Navigator.pop(context, result.contacts),
          child: Text(c.t('استيراد', 'Import')),
        ),
      ],
    );
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.c});
  final RelayController c;
  String status(String s) {
    const ar = {
      'queued': 'في الانتظار',
      'accepted': 'مقبول',
      'sent': 'تم الإرسال',
      'delivered': 'تم التسليم',
      'read': 'مقروء',
      'failed': 'فشل',
      'undelivered': 'لم يتم التسليم',
      'unknown': 'غير مؤكد — افحص Twilio',
      'submitting': 'قيد التقديم — افحص Twilio',
      'canceled': 'ملغى',
      'pending': 'لم يُقدّم',
      'sending': 'جارٍ الإرسال',
    };
    return c.settings.language == 'en'
        ? (s == 'submitting' ? 'Submitting — check Twilio' : s)
        : ar[s] ?? s;
  }

  Future<void> resume(BuildContext context, SendRun run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.t('إرسال الجهات المتبقية؟', 'Send remaining contacts?')),
        content: Text(
          c.t(
            'أكد أن الموافقة ما زالت سارية وأن القالب معتمد، أو أن كل جهة متبقية راسلتك خلال آخر 24 ساعة. لن يُعاد إرسال أي طلب سابق.',
            'Confirm consent is still valid and your template is approved, or every remaining recipient messaged you within the last 24 hours. Existing attempts will not be retried.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(c.t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(c.t('تأكيد وإرسال', 'Confirm & send')),
          ),
        ],
      ),
    );
    if (ok == true) await c.process(run);
  }

  @override
  Widget build(BuildContext context) => PageBody(
    title: c.t('سجل الإرسال', 'Activity'),
    subtitle: c.t(
      'في الانتظار لا يعني تم التسليم. حدّث الحالة من Twilio.',
      'Queued is not delivered. Refresh statuses from Twilio.',
    ),
    children: [
      if (c.sending)
        Section(
          title: c.t('جارٍ الإرسال…', 'Sending…'),
          children: [
            Text(c.activeRun?.name ?? ''),
            gap(),
            LinearProgressIndicator(
              value: c.activeRun == null
                  ? null
                  : c.activeRun!.attempts.length / c.activeRun!.contacts.length,
            ),
            gap(),
            Text(
              '${c.activeRun?.attempts.length} / ${c.activeRun?.contacts.length}',
            ),
            gap(),
            OutlinedButton(
              onPressed: c.paused ? null : c.pause,
              child: Text(
                c.t(
                  c.paused ? 'جارٍ الإيقاف بعد الطلب الحالي' : 'إيقاف مؤقت',
                  c.paused ? 'Pausing after current request' : 'Pause',
                ),
              ),
            ),
          ],
        ),
      if (c.error != null) hint(c.error!),
      if (c.runs.isEmpty)
        Section(
          title: c.t('لم تُرسل رسائل بعد', 'No sends yet'),
          children: [
            Text(
              c.t(
                'تظهر هنا الرسائل بعد مراجعتها وتأكيد إرسالها.',
                'Your reviewed and confirmed sends appear here.',
              ),
            ),
          ],
        ),
      ...c.runs.map(
        (r) => Section(
          title: r.name,
          subtitle:
              '${r.created.toLocal().toString().split('.').first} · ${r.contacts.length} ${c.t('مستلم', 'recipients')}',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: c.sending || c.refreshing
                      ? null
                      : () => protect(context, () => c.refresh(r)),
                  icon: const Icon(Icons.refresh),
                  label: Text(c.t('تحديث الحالات', 'Refresh statuses')),
                ),
                OutlinedButton.icon(
                  onPressed: () => protect(
                    context,
                    () => exportCsv(
                      context,
                      'relay-results-${r.created.millisecondsSinceEpoch}.csv',
                      [
                        ['name', 'phone', 'status', 'message_sid', 'error'],
                        ...r.contacts.map((p) {
                          final a = r.attempts[p.id];
                          return [
                            p.name,
                            p.phone,
                            a?.status ?? 'pending',
                            a?.sid ?? '',
                            a?.error ?? '',
                          ];
                        }),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.download),
                  label: Text(c.t('تصدير النتائج', 'Export results')),
                ),
                if (r.pending.isNotEmpty)
                  FilledButton(
                    onPressed: c.sending
                        ? null
                        : () => protect(context, () => resume(context, r)),
                    child: Text(
                      '${c.t('إرسال المتبقي', 'Send remaining')} (${r.pending.length})',
                    ),
                  ),
              ],
            ),
            hint(
              c.t(
                'الطلبات غير المؤكدة لا تُعاد تلقائياً. افحص سجل Twilio قبل إنشاء إرسال جديد. أبقِ التطبيق مفتوحاً أثناء الإرسال.',
                'Uncertain attempts never retry automatically. Check Twilio logs before creating a new send. Keep the app open while sending.',
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(c.t('تفاصيل المستلمين', 'Recipient details')),
              children: r.contacts.map((p) {
                final a = r.attempts[p.id];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p.name} · ${p.phone}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(status(a?.status ?? 'pending')),
                      if (a != null && a.error.isNotEmpty)
                        Text(
                          '${a.code} ${a.error}',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      if (a?.sid.isNotEmpty ?? false)
                        SelectableText(
                          a!.sid,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ],
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.c});
  final RelayController c;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  RelayController get c => widget.c;
  late final brand = TextEditingController(text: c.settings.brand),
      code = TextEditingController(text: c.settings.countryCode),
      account = TextEditingController(text: c.settings.accountSid),
      sender = TextEditingController(text: c.settings.sender),
      key = TextEditingController(text: c.settings.apiKeySid),
      secret = TextEditingController();
  late String auth = c.settings.authMode;
  bool busy = false;
  @override
  void dispose() {
    for (final t in [brand, code, account, sender, key, secret]) {
      t.dispose();
    }
    super.dispose();
  }

  Settings collect() {
    final s = c.settings.copy()
      ..brand = brand.text.trim()
      ..countryCode = code.text.replaceAll('+', '').trim()
      ..accountSid = account.text.trim()
      ..sender = sender.text.trim()
      ..apiKeySid = key.text.trim()
      ..authMode = auth;
    if (auth != c.settings.authMode && secret.text.trim().isEmpty) {
      throw StateError(
        c.t(
          'أدخل السر الخاص بطريقة المصادقة الجديدة',
          'Enter the secret for the new authentication method.',
        ),
      );
    }
    if (secret.text.trim().isNotEmpty) s.secret = secret.text.trim();
    return s;
  }

  Future<void> save({bool test = false}) async {
    setState(() => busy = true);
    try {
      await c.saveSettings(collect());
      secret.clear();
      if (test) await c.api.test(c.settings);
      if (mounted) {
        notice(
          context,
          test
              ? c.t(
                  'تم الحفظ ونجح اختبار API. لا يثبت ذلك اعتماد رقم واتساب أو تسليم الرسائل.',
                  'Saved and API access verified. This does not verify WhatsApp sender approval or delivery.',
                )
              : c.t(
                  'تم حفظ الإعدادات والأسرار على هذا الجهاز',
                  'Settings and secrets saved on this device',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool password = false,
    String? placeholder,
    bool ltr = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 19),
    child: TextField(
      controller: controller,
      obscureText: password,
      enableSuggestions: !password,
      autocorrect: !password,
      textDirection: ltr ? TextDirection.ltr : null,
      decoration: InputDecoration(labelText: label, hintText: placeholder),
      keyboardType: password ? TextInputType.visiblePassword : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PageBody(
    title: c.t('الإعدادات', 'Settings'),
    subtitle: c.t(
      'تعمل هذه النسخة من جهازك مباشرة. لا خادم ولا صفحة معاينة.',
      'This native app works directly from your device. No custom server or preview page.',
    ),
    children: [
      Section(
        title: c.t('بيانات Twilio', 'Twilio account'),
        subtitle: c.t(
          'تُحفظ الأسرار في مخزن النظام الآمن. اترك حقل السر فارغاً للاحتفاظ بالمحفوظ.',
          'Secrets use the operating system secure storage. Leave a secret blank to keep the saved value.',
        ),
        children: [
          field(account, 'Account SID', placeholder: 'AC…'),
          field(
            sender,
            c.t('رقم واتساب المعتمد', 'Approved WhatsApp sender'),
            placeholder: '+9647…',
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: auth,
            decoration: InputDecoration(
              labelText: c.t('المصادقة', 'Authentication'),
            ),
            items: [
              DropdownMenuItem(
                value: 'key',
                child: Text(
                  c.t('مفتاح API (موصى به)', 'API key (recommended)'),
                ),
              ),
              const DropdownMenuItem(
                value: 'token',
                child: Text('Account Auth Token'),
              ),
            ],
            onChanged: (v) => setState(() => auth = v!),
          ),
          gap(),
          if (auth == 'key') field(key, 'API Key SID', placeholder: 'SK…'),
          field(
            secret,
            auth == 'key' ? 'API Key Secret' : 'Auth Token',
            password: true,
            placeholder: c.settings.secret.isNotEmpty
                ? c.t(
                    'محفوظ — اتركه فارغاً للاحتفاظ به',
                    'Saved — leave blank to keep',
                  )
                : '',
          ),
          hint(
            c.t(
              'استخدم بيانات منطقة Twilio الافتراضية US1. اختبار الاتصال يقرأ حالة API ولا يرسل رسالة.',
              'Use credentials for the default Twilio US1 region. The connection test reads API access and does not send a message.',
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy || c.sending || c.mediaBusy
                    ? null
                    : () => protect(context, () => save()),
                icon: const Icon(Icons.save_outlined),
                label: Text(c.t('حفظ الإعدادات', 'Save settings')),
              ),
              OutlinedButton.icon(
                onPressed: busy || c.sending || c.mediaBusy
                    ? null
                    : () => protect(context, () => save(test: true)),
                icon: const Icon(Icons.link),
                label: Text(
                  c.t('حفظ واختبار الاتصال', 'Save & test connection'),
                ),
              ),
            ],
          ),
        ],
      ),
      Section(
        title: c.t('التفضيلات', 'Preferences'),
        children: [
          field(brand, c.t('اسم النشاط', 'Business name'), ltr: false),
          field(
            code,
            c.t('رمز الدولة الافتراضي', 'Default country code'),
            placeholder: '964',
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(c.settings.language),
            initialValue: c.settings.language,
            decoration: InputDecoration(labelText: c.t('اللغة', 'Language')),
            items: const [
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => protect(context, () => c.setLanguage(v!)),
          ),
          hint(
            c.t(
              'العراق +964 هو الافتراضي. جهات الاتصال والسجل محفوظة محلياً ولا تتزامن تلقائياً بين الأجهزة.',
              'Iraq +964 is the default. Contacts and history stay on this device and do not automatically sync.',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: busy || c.sending || c.mediaBusy
                  ? null
                  : () => protect(context, () => save()),
              child: Text(c.t('حفظ التفضيلات', 'Save preferences')),
            ),
          ),
        ],
      ),
      Section(
        title: c.t('الصور عبر Twilio', 'Photos through Twilio'),
        children: [
          Text(
            c.t(
              'لا تحتاج حساب صور منفصل. يستخدم التطبيق Twilio Functions & Assets لإنشاء روابط عامة لصور JPG وPNG حتى 5 MB.',
              'No separate image account is needed. The app uses Twilio Functions & Assets to create public links for JPG and PNG photos up to 5 MB.',
            ),
          ),
          hint(
            c.t(
              'يلزم مفتاح يسمح بالوصول إلى Functions & Assets وContent API للقوالب. قد تطبق حدود ورسوم Twilio. الصور لا تُحذف تلقائياً؛ يمكنك إدارتها من لوحة Twilio.',
              'Your key needs Functions & Assets access, and Content API access for templates. Twilio limits and charges may apply. Photos are not automatically deleted; manage them in the Twilio console.',
            ),
          ),
          if (c.settings.mediaServiceSid.isNotEmpty)
            SelectableText(
              'Service: ${c.settings.mediaServiceSid}',
              textDirection: TextDirection.ltr,
            ),
        ],
      ),
    ],
  );
}
