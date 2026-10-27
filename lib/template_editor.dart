import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'domain.dart';
import 'templates.dart';
import 'photo_recovery.dart';

String templateStatus(RelayController c, String value) => switch (value) {
  'approved' => c.t('معتمد وجاهز للإرسال', 'Approved, ready to send'),
  'received' ||
  'pending' ||
  'in_review' => c.t('قيد مراجعة واتساب', 'Awaiting WhatsApp approval'),
  'unsubmitted' => c.t('محفوظ، يحتاج طلب اعتماد', 'Saved, request approval'),
  'rejected' => c.t(
    'مرفوض — راجع السبب وعدّل نسخة',
    'Rejected — check the reason and edit a copy',
  ),
  'paused' || 'disabled' => c.t(
    'متوقف — راجع لوحة Twilio',
    'Paused — check Twilio console',
  ),
  _ => c.t('حدّث الحالة قبل الإرسال', 'Refresh status before sending'),
};

class TemplatePhotos extends StatelessWidget {
  const TemplatePhotos({
    super.key,
    required this.value,
    required this.values,
    required this.contact,
  });
  final WhatsAppTemplate value;
  final Map<String, String> values;
  final Contact contact;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final source in value.media)
        if (isPublicHttps(value.render(source, values, contact)))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Image.network(
              value.render(source, values, contact),
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Text('تعذر عرض الصورة / Unable to display photo'),
            ),
          ),
    ],
  );
}

class TemplateLinks extends StatelessWidget {
  const TemplateLinks({
    super.key,
    required this.value,
    required this.values,
    required this.contact,
  });
  final WhatsAppTemplate value;
  final Map<String, String> values;
  final Contact contact;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final link in value.links)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('${link['title']}'),
            onPressed: () async {
              final url = value.render('${link['url']}', values, contact);
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (!isPublicHttps(url) ||
                    !await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    )) {
                  throw StateError('Unable to open link');
                }
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تعذر فتح الرابط / Unable to open link'),
                  ),
                );
              }
            },
          ),
        ),
    ],
  );
}

class TemplatePanel extends StatefulWidget {
  const TemplatePanel({
    super.key,
    required this.c,
    required this.onSelected,
    required this.onValues,
  });
  final RelayController c;
  final void Function(WhatsAppTemplate, Map<String, String>) onSelected;
  final void Function(Map<String, String>) onValues;
  @override
  State<TemplatePanel> createState() => _TemplatePanelState();
}

class _TemplatePanelState extends State<TemplatePanel> {
  RelayController get c => widget.c;
  TemplateApi get api => TemplateApi(c.api.client);
  final items = <WhatsAppTemplate>[];
  final inputs = <String, TextEditingController>{};
  final values = <String, String>{};
  WhatsAppTemplate? selected;
  bool busy = false;
  String? error;
  String account = '';
  @override
  void initState() {
    super.initState();
    account = c.settings.accountSid;
    if (c.draft.templateData.isNotEmpty) {
      selected = WhatsAppTemplate(c.draft.templateData);
      items.add(selected!);
      setInputs(selected!, safeVariables(c.draft.variables));
    }
  }

  @override
  void didUpdateWidget(covariant TemplatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (account != c.settings.accountSid) {
      account = c.settings.accountSid;
      items.clear();
      selected = null;
      setInputs(WhatsAppTemplate({}), {});
    }
  }

  void setInputs(WhatsAppTemplate value, Map<String, String> initial) {
    for (final input in inputs.values) {
      input.dispose();
    }
    inputs.clear();
    values.clear();
    for (final slot in value.slots) {
      final text = initial[slot] ?? value.samples[slot] ?? '';
      values[slot] = text;
      inputs[slot] = TextEditingController(text: text);
    }
  }

  @override
  void dispose() {
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final config = c.settings.copy();
    final loaded = await api.list(config);
    if (!mounted || c.settings.accountSid != config.accountSid) return;
    setState(() {
      items.clear();
      items.addAll(loaded);
      if (selected != null && !items.any((v) => v.sid == selected!.sid)) {
        items.add(selected!);
      }
    });
  }

  Future<void> choose(WhatsAppTemplate value) async {
    final config = c.settings.copy();
    final fresh = await api.refresh(config, value);
    if (!mounted || c.settings.accountSid != config.accountSid) return;
    setState(() {
      selected = fresh;
      setInputs(
        fresh,
        fresh.sid == c.draft.contentSid ? safeVariables(c.draft.variables) : {},
      );
    });
    widget.onSelected(fresh, Map.from(values));
  }

  Future<void> create({bool copy = false}) async {
    final result = await showDialog<WhatsAppTemplate>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TemplateDialog(c: c, source: copy ? selected : null),
    );
    if (result == null || !mounted) return;
    setState(() {
      items.removeWhere((v) => v.sid == result.sid);
      items.add(result);
      selected = result;
      setInputs(result, {});
    });
    widget.onSelected(result, Map.from(values));
    await c.save();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        c.t(
          'اختر قالبك واملأ التفاصيل — دون أكواد',
          'Choose a template and fill in the details — no code needed',
        ),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : () => perform(load),
            icon: const Icon(Icons.sync),
            label: Text(
              c.t('تحميل قوالبي من Twilio', 'Load my Twilio templates'),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: busy || !c.settings.connected
                ? null
                : () => perform(() => create()),
            icon: const Icon(Icons.add),
            label: Text(
              c.t('قالب جديد + أزرار روابط', 'New template + link buttons'),
            ),
          ),
        ],
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: LinearProgressIndicator(),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('${selected?.sid}:${items.length}'),
          initialValue: selected?.sid,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: c.t('القالب المحفوظ', 'Saved template'),
          ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item.sid,
                child: Text(
                  '${item.name} · ${item.language}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy
              ? null
              : (sid) => perform(
                  () => choose(items.firstWhere((v) => v.sid == sid)),
                ),
        ),
      ],
      if (selected != null) ...[
        const SizedBox(height: 12),
        Text(
          templateStatus(c, selected!.status),
          style: TextStyle(
            color: selected!.status == 'approved'
                ? const Color(0xff176c45)
                : Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        if ('${selected!.data['relay_reason'] ?? ''}'.isNotEmpty)
          Text('${selected!.data['relay_reason']}'),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => perform(() => choose(selected!)),
              icon: const Icon(Icons.refresh),
              label: Text(c.t('تحديث الاعتماد', 'Refresh approval')),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => perform(() => create(copy: true)),
              icon: const Icon(Icons.edit_outlined),
              label: Text(c.t('تعديل نسخة + الروابط', 'Edit a copy + links')),
            ),
            if (selected!.status == 'unsubmitted')
              TextButton(
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        final result = await showDialog<WhatsAppTemplate>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              TemplateDialog(c: c, existing: selected),
                        );
                        if (result != null && mounted) {
                          setState(() => selected = result);
                          widget.onSelected(result, Map.from(values));
                          await c.save();
                        }
                      }),
                child: Text(c.t('طلب اعتماد', 'Request approval')),
              ),
          ],
        ),
        for (final slot in selected!.slots) ...[
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('template-value-$slot'),
            controller: inputs[slot],
            onChanged: (text) {
              values[slot] = text;
              widget.onValues(Map.from(values));
            },
            decoration: InputDecoration(
              labelText: '${c.t('التفصيل', 'Detail')} $slot',
              helperText:
                  '${c.t('مثال', 'Example')}: ${selected!.samples[slot] ?? ''}',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () {
                  inputs[slot]!.text = '{{name}}';
                  values[slot] = '{{name}}';
                  widget.onValues(Map.from(values));
                },
                child: Text(c.t('اسم كل مستلم', 'Each recipient’s name')),
              ),
              TextButton(
                onPressed: () {
                  inputs[slot]!.text = '{{phone}}';
                  values[slot] = '{{phone}}';
                  widget.onValues(Map.from(values));
                },
                child: Text(c.t('رقم كل مستلم', 'Each recipient’s phone')),
              ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            c.t(
              'نص القالب وأزراره مرتبطان باعتماد واتساب. لتغييرهما اختر تعديل نسخة. املأ التفاصيل أعلاه لكل إرسال.',
              'Template wording and buttons belong to its WhatsApp approval. Use Edit a copy to change them. Fill in the details above for each send.',
            ),
          ),
        ),
      ],
    ],
  );
}

class TemplateDialog extends StatefulWidget {
  const TemplateDialog({
    super.key,
    required this.c,
    this.source,
    this.existing,
  });
  final RelayController c;
  final WhatsAppTemplate? source, existing;
  @override
  State<TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<TemplateDialog> {
  RelayController get c => widget.c;
  late final config = c.settings.copy();
  late final name = TextEditingController(
    text:
        widget.existing?.name ??
        (widget.source == null
            ? ''
            : '${widget.source!.name} ${c.t('نسخة', 'copy')}'),
  );
  late final body = TextEditingController(
    text:
        widget.existing?.body ??
        widget.source?.body ??
        c.t(
          'مرحباً {{1}}، شكراً لتواصلك معنا.',
          'Hello {{1}}, thank you for contacting us.',
        ),
  );
  final approval = TextEditingController(
    text: 'relay_${DateTime.now().millisecondsSinceEpoch}',
  );
  final sampleInputs = <String, TextEditingController>{};
  late final photo = TextEditingController(
    text: (widget.existing ?? widget.source)?.media.firstOrNull ?? '',
  );
  final titles = <TextEditingController>[], urls = <TextEditingController>[];
  late String language =
      widget.existing?.language ??
      widget.source?.language ??
      c.settings.language;
  String category = 'MARKETING';
  String? error;
  String photoProgress = '';
  bool busy = false, uncertainCreate = false;
  late WhatsAppTemplate? created = widget.existing;
  List<String> get slots =>
      RegExp(r'\{\{(\d+)\}\}')
          .allMatches(body.text)
          .map((m) => m[1]!)
          .toSet()
          .toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  @override
  void initState() {
    super.initState();
    final source = widget.existing ?? widget.source;
    for (final link in source?.links ?? <Map<String, dynamic>>[]) {
      titles.add(TextEditingController(text: '${link['title']}'));
      urls.add(TextEditingController(text: '${link['url']}'));
    }
    for (final slot in slots) {
      sampleInputs[slot] = TextEditingController(
        text: source?.samples[slot] ?? (slot == '1' ? c.t('علي', 'Ali') : ''),
      );
    }
  }

  void syncSamples() {
    for (final slot in slots) {
      sampleInputs.putIfAbsent(slot, () => TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final t in [
      name,
      body,
      approval,
      photo,
      ...sampleInputs.values,
      ...titles,
      ...urls,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    try {
      final value = await TemplateApi(c.api.client).create(
        config,
        name: name.text,
        language: language,
        body: body.text,
        mediaUrl: photo.text.trim(),
        samples: {for (final slot in slots) slot: sampleInputs[slot]!.text},
        links: [
          for (var n = 0; n < titles.length; n++)
            {'title': titles[n].text, 'url': urls[n].text},
        ],
      );
      if (mounted) setState(() => created = value);
    } catch (e) {
      // Validation is local. A network exception may follow a successful creation;
      // require checking the saved list rather than repeating an uncertain POST.
      if (e is ContentFailure && e.uncertain) {
        uncertainCreate = true;
      }
      rethrow;
    }
  }

  Future<void> submit() async {
    final result = await TemplateApi(c.api.client)
        .submit(config, created!, approval.text.trim(), category);
    if (mounted) setState(() => created = result);
  }

  Future<void> uploadPhoto() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final size = await file.length();
    if (size != null && size > 5 * 1024 * 1024) {
      throw const FormatException('5 MB maximum');
    }
    final url = await c.uploadPhoto(
      await file.readAsBytes(),
      file.name,
      onProgress: (message) {
        if (mounted) setState(() => photoProgress = message);
      },
    );
    if (mounted) setState(() => photo.text = url);
  }

  @override
  Widget build(BuildContext context) {
    final preview = WhatsAppTemplate({
      'types': {
        titles.isEmpty ? 'twilio/text' : 'twilio/call-to-action': {
          'body': body.text,
          'actions': [
            for (var n = 0; n < titles.length; n++)
              {'type': 'URL', 'title': titles[n].text, 'url': urls[n].text},
          ],
        },
      },
    });
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          c.t('إنشاء قالب وأزرار روابط', 'Create a template and link buttons'),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.t(
                    '1. اكتب النص وأضف الروابط. 2. احفظ القالب في Twilio. 3. اطلب اعتماد واتساب. لن تُرسل رسالة هنا.',
                    '1. Write your text and add links. 2. Save the template to Twilio. 3. Request WhatsApp approval. No message is sent here.',
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: name,
                  enabled: created == null && !busy,
                  decoration: InputDecoration(
                    labelText: c.t('اسم واضح للقالب', 'Template name'),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: ['ar', 'en'].contains(language)
                      ? language
                      : 'ar',
                  decoration: InputDecoration(
                    labelText: c.t('لغة الرسالة', 'Message language'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: created != null || busy
                      ? null
                      : (v) => setState(() => language = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: body,
                  enabled: created == null && !busy,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: titles.isEmpty ? 1600 : 640,
                  onChanged: (_) => setState(syncSamples),
                  decoration: InputDecoration(
                    labelText: c.t('نص الرسالة', 'Message text'),
                  ),
                ),
                if (created == null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(
                        c.t('إضافة تفصيل متغير', 'Add variable detail'),
                      ),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              var n = 1;
                              while (slots.contains('$n')) {
                                n++;
                              }
                              body.text = '${body.text} {{$n}}';
                              syncSamples();
                            }),
                    ),
                  ),
                for (final slot in slots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: sampleInputs[slot],
                      enabled: created == null && !busy,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText:
                            '${c.t('مثال للتفصيل', 'Sample for detail')} $slot',
                        helperText: c.t(
                          'مثال حقيقي الشكل لمراجعة واتساب؛ مثل علي للاسم.',
                          'A realistic example for WhatsApp review, such as Ali for a name.',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (created == null)
                  PhotoRecovery(
                    c: c,
                    onVerified: (url) => setState(() => photo.text = url),
                  ),
                TextField(
                  controller: photo,
                  enabled: created == null && !busy,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: c.t(
                      'رابط صورة للقالب (اختياري)',
                      'Template photo URL (optional)',
                    ),
                    hintText: 'https://…/photo.jpg',
                  ),
                ),
                if (created == null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: busy || c.mediaBusy
                          ? null
                          : () => run(uploadPhoto),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        c.t(
                          'رفع صورة عبر Twilio',
                          'Upload photo through Twilio',
                        ),
                      ),
                    ),
                  ),
                if (photoProgress.isNotEmpty) Text(photoProgress),
                Text(
                  c.t(
                    'الصورة تصبح جزءاً من القالب. لتغييرها بعد الاعتماد أنشئ نسخة. الصور المرفوعة عامة لمن لديه الرابط.',
                    'The photo becomes part of this template. To change it after approval, create a copy. Uploaded photos are public to anyone with the URL.',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  c.t(
                    'أزرار المواقع (اختيارية، حتى زرين)',
                    'Website buttons (optional, up to two)',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var n = 0; n < titles.length; n++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: ValueKey('button-label-$n'),
                            controller: titles[n],
                            enabled: created == null && !busy,
                            maxLength: 20,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText:
                                  '${c.t('عنوان الزر', 'Button label')} ${n + 1}',
                              hintText: c.t('زيارة الموقع', 'Visit website'),
                            ),
                          ),
                          TextField(
                            key: ValueKey('button-url-$n'),
                            controller: urls[n],
                            enabled: created == null && !busy,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.url,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: c.t(
                                'رابط الموقع الكامل',
                                'Full website link',
                              ),
                              hintText: 'https://example.com',
                            ),
                          ),
                          if (created == null)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        titles.removeAt(n).dispose();
                                        urls.removeAt(n).dispose();
                                      }),
                                child: Text(c.t('إزالة الزر', 'Remove button')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (titles.length < 2 && created == null)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            titles.add(TextEditingController());
                            urls.add(TextEditingController());
                          }),
                    icon: const Icon(Icons.add_link),
                    label: Text(c.t('إضافة زر رابط', 'Add website button')),
                  ),
                const SizedBox(height: 16),
                Text(
                  c.t('معاينة', 'Preview'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xffe9f2e6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isPublicHttps(photo.text))
                        Image.network(
                          photo.text,
                          height: 150,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Text(
                            c.t('تعذر عرض الصورة', 'Unable to display photo'),
                          ),
                        ),
                      Text(
                        preview.render(
                          body.text,
                          {
                            for (final slot in slots)
                              slot: sampleInputs[slot]!.text,
                          },
                          Contact(
                            name: c.t('علي', 'Ali'),
                            phone: '+9647700000000',
                          ),
                        ),
                      ),
                      for (final title in titles)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_in_new, size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  title.text.isEmpty
                                      ? c.t('عنوان الزر', 'Button label')
                                      : title.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (created != null) ...[
                  Text(
                    templateStatus(c, created!.status),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText(
                    created!.sid,
                    textDirection: TextDirection.ltr,
                  ),
                  if (created!.status == 'unsubmitted') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: approval,
                      enabled: !busy,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: c.t(
                          'اسم الاعتماد بالإنجليزية (مجهز لك)',
                          'English approval name (filled for you)',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: c.t('نوع الرسالة', 'Message category'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'MARKETING',
                          child: Text(
                            c.t('تسويق وعروض', 'Marketing and offers'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'UTILITY',
                          child: Text(
                            c.t('تحديث طلب أو خدمة', 'Order or service update'),
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => category = v!),
                    ),
                  ],
                  Text(
                    c.t(
                      'الاعتماد ليس فورياً. أغلق هذه النافذة وحدّث الحالة من صفحة الرسالة لاحقاً. تعديل النص أو الروابط ينشئ نسخة جديدة تحتاج اعتماداً.',
                      'Approval is not immediate. Close this window and refresh approval from the message page later. Editing wording or links creates a new copy requiring approval.',
                    ),
                  ),
                ],
                if (uncertainCreate)
                  Text(
                    c.t(
                      'لم نتأكد من نتيجة الحفظ. أغلق النافذة وحمّل قوالبك للتحقق قبل إنشاء نسخة أخرى.',
                      'Save result is uncertain. Close this window and load your templates before creating another copy.',
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SelectableText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, created),
            child: Text(c.t('إغلاق', 'Close')),
          ),
          if (created == null)
            FilledButton(
              onPressed: busy || uncertainCreate ? null : () => run(save),
              child: Text(
                c.t('حفظ القالب في Twilio', 'Save template to Twilio'),
              ),
            ),
          if (created?.status == 'unsubmitted')
            FilledButton(
              onPressed: busy ? null : () => run(submit),
              child: Text(
                c.t('طلب اعتماد واتساب', 'Request WhatsApp approval'),
              ),
            ),
        ],
      ),
    );
  }
}
