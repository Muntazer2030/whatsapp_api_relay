import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'services.dart';
import 'templates.dart';
import 'photo_probe.dart';

class RelayController extends ChangeNotifier {
  RelayController({required this.repository, TwilioApi? api})
    : api = api ?? TwilioApi();
  final Repository repository;
  final TwilioApi api;
  Settings settings = Settings();
  Draft draft = Draft();
  final contacts = <Contact>[];
  final runs = <SendRun>[];
  bool ready = false,
      sending = false,
      paused = false,
      refreshing = false,
      mediaBusy = false;
  String? error;
  SendRun? activeRun;

  String t(String ar, String en) => settings.language == 'en' ? en : ar;
  Future<void> initialize() async {
    try {
      final state = await repository.load();
      settings = Settings.fromJson(
        Map<String, dynamic>.from(state['settings'] ?? {}),
        await repository.loadSecrets(),
      );
      draft = Draft.fromJson(Map<String, dynamic>.from(state['draft'] ?? {}));
      contacts.addAll(
        (state['contacts'] as List? ?? []).map(
          (c) => Contact.fromJson(Map<String, dynamic>.from(c)),
        ),
      );
      runs.addAll(
        (state['runs'] as List? ?? []).map(
          (r) => SendRun.fromJson(Map<String, dynamic>.from(r)),
        ),
      );
      ready = true;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Map<String, dynamic> snapshot() => {
    'version': 1,
    'settings': settings.toJson(),
    'draft': draft.toJson(),
    'contacts': contacts.map((c) => c.toJson()).toList(),
    'runs': runs.map((r) => r.toJson()).toList(),
  };
  Future<void> save() => repository.save(snapshot());
  Future<void> saveSettings(Settings value) async {
    if (sending || mediaBusy) {
      throw StateError(t('أوقف الإرسال أولاً', 'Pause sending first.'));
    }
    if (!RegExp(r'^\d{1,4}$').hasMatch(value.countryCode)) {
      throw FormatException(t('رمز دولة غير صالح', 'Invalid country code'));
    }
    if (value.sender.isNotEmpty &&
        normalizePhone(value.sender) != value.sender) {
      throw FormatException(
        t(
          'أدخل رقم المرسل بصيغة +964…',
          'Use an international sender number, +964…',
        ),
      );
    }
    if (value.accountSid.isNotEmpty &&
        !RegExp(
          r'^AC[0-9a-f]{32}$',
          caseSensitive: false,
        ).hasMatch(value.accountSid)) {
      throw const FormatException('Account SID: AC + 32 hex characters');
    }
    if (value.apiKeySid.isNotEmpty &&
        !RegExp(
          r'^SK[0-9a-f]{32}$',
          caseSensitive: false,
        ).hasMatch(value.apiKeySid)) {
      throw const FormatException('API Key SID: SK + 32 hex characters');
    }
    await repository.saveSecrets(value.secrets());
    final old = settings;
    settings = value;
    try {
      await save();
    } catch (_) {
      settings = old;
      await repository.saveSecrets(old.secrets());
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    settings.language = language;
    notifyListeners();
    await save();
  }

  Future<String> uploadPhoto(
    Uint8List bytes,
    String name, {
    void Function(String)? onProgress,
  }) async {
    if (mediaBusy || sending) {
      throw StateError(
        t('انتظر انتهاء العملية الحالية', 'Wait for the current operation.'),
      );
    }
    mediaBusy = true;
    notifyListeners();
    final config = settings.copy();
    try {
      return await api.upload(
        config,
        bytes,
        name,
        onProgress: onProgress,
        persistConfiguration: () async {
          if (settings.accountSid != config.accountSid) {
            throw StateError('Account changed during upload');
          }
          // Persist created resources immediately so an interrupted upload can reuse them.
          settings.mediaServiceSid = config.mediaServiceSid;
          settings.mediaEnvironmentSid = config.mediaEnvironmentSid;
          settings.mediaAccountSid = config.mediaAccountSid;
          settings.lastPhotoUrl = config.lastPhotoUrl;
          settings.lastPhotoPending = config.lastPhotoPending;
          settings.lastPhotoError = config.lastPhotoError;
          await save();
        },
      );
    } finally {
      mediaBusy = false;
      notifyListeners();
    }
  }

  Future<String> retryPhotoCheck({void Function(String)? onProgress}) async {
    if (mediaBusy || sending) {
      throw StateError(
        t('انتظر انتهاء العملية الحالية', 'Wait for the current operation.'),
      );
    }
    if (settings.mediaAccountSid != settings.accountSid ||
        settings.lastPhotoUrl.isEmpty) {
      throw StateError(
        t(
          'لا يوجد رابط صورة محفوظ لهذا الحساب',
          'No photo link is saved for this account.',
        ),
      );
    }
    mediaBusy = true;
    notifyListeners();
    final config = settings.copy();
    try {
      final url = await api.verifyPhoto(
        config,
        config.lastPhotoUrl,
        onProgress: onProgress,
      );
      settings.lastPhotoPending = false;
      settings.lastPhotoError = '';
      await save();
      return url;
    } on PhotoCheckFailure catch (e) {
      settings.lastPhotoPending = true;
      settings.lastPhotoError = e.detail;
      await save();
      rethrow;
    } finally {
      mediaBusy = false;
      notifyListeners();
    }
  }

  Future<void> addContacts(List<Contact> values) async {
    if (contacts.length + values.length > 5000) {
      throw StateError(
        t('الحد الأقصى 5,000 جهة اتصال', 'Maximum 5,000 contacts'),
      );
    }
    final seen = contacts.map((c) => c.phone).toSet();
    if (values.any(
      (c) => normalizePhone(c.phone) != c.phone || !seen.add(c.phone),
    )) {
      throw StateError(t('رقم غير صالح أو مكرر', 'Invalid or duplicate phone'));
    }
    contacts.addAll(values);
    try {
      await save();
    } catch (_) {
      contacts.removeWhere((c) => values.contains(c));
      rethrow;
    }
    notifyListeners();
  }

  Future<void> changeContact(Contact c, {bool? consent, bool? selected}) async {
    final oldConsent = c.consent, oldSelected = c.selected;
    c.consent = consent ?? c.consent;
    c.selected = selected ?? c.selected;
    try {
      await save();
    } catch (_) {
      c.consent = oldConsent;
      c.selected = oldSelected;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> selectContacts(Iterable<Contact> list, bool value) async {
    final old = {for (final c in list) c.id: c.selected};
    for (final c in list) {
      c.selected = value;
    }
    try {
      await save();
    } catch (_) {
      for (final c in list) {
        c.selected = old[c.id]!;
      }
      rethrow;
    }
    notifyListeners();
  }

  Future<void> deleteContact(Contact c) async {
    final index = contacts.indexOf(c);
    contacts.remove(c);
    try {
      await save();
    } catch (_) {
      contacts.insert(index, c);
      rethrow;
    }
    notifyListeners();
  }

  void validateDraft(
    Draft d,
    List<Contact> audience,
    bool consent,
    bool window,
  ) {
    if (!settings.connected) {
      throw StateError(
        t(
          'احفظ بيانات Twilio في الإعدادات أولاً',
          'Save Twilio credentials in Settings first.',
        ),
      );
    }
    if (audience.isEmpty) {
      throw StateError(
        t('حدد جهة اتصال واحدة على الأقل', 'Select at least one contact.'),
      );
    }
    if (audience.any((c) => !c.consent)) {
      throw StateError(
        t(
          'سجّل موافقة كل جهة محددة',
          'Record consent for every selected contact.',
        ),
      );
    }
    if (!consent) {
      throw StateError(t('أكد موافقة المستلمين', 'Confirm recipient consent.'));
    }
    if (d.template) {
      if (!RegExp(
        r'^HX[0-9a-f]{32}$',
        caseSensitive: false,
      ).hasMatch(d.contentSid.trim())) {
        throw const FormatException('Content SID: HX + 32 hex characters');
      }
      d.parsedVariables();
      if (d.templateData.isNotEmpty) {
        final value = WhatsAppTemplate(d.templateData);
        if (value.sid != d.contentSid || value.status != 'approved') {
          throw StateError(
            t(
              'انتظر اعتماد واتساب ثم حدّث حالة القالب.',
              'Wait for WhatsApp approval, then refresh the template status.',
            ),
          );
        }
        final values = d.parsedVariables();
        if (value.slots.any((slot) => (values[slot] ?? '').trim().isEmpty)) {
          throw StateError(
            t(
              'املأ كل تفاصيل القالب أولاً.',
              'Fill in every template detail first.',
            ),
          );
        }
      }
    } else {
      if (!window) {
        throw StateError(
          t('أكد نافذة الرد خلال 24 ساعة', 'Confirm the 24-hour reply window.'),
        );
      }
      if (d.body.trim().isEmpty && d.mediaUrl.trim().isEmpty) {
        throw StateError(t('أضف نصاً أو صورة', 'Add a message or photo.'));
      }
      if (d.mediaUrl.isNotEmpty && !isPublicHttps(d.mediaUrl)) {
        throw StateError(
          t('استخدم رابط صورة HTTPS عاماً', 'Use a public HTTPS image URL.'),
        );
      }
      if (d.body.length > 1600) {
        throw StateError(
          t('النص أطول من 1600 حرف', 'Message exceeds 1600 characters.'),
        );
      }
    }
  }

  Future<SendRun> createRun(
    Draft d,
    List<Contact> audience,
    bool consent,
    bool window,
  ) async {
    if (sending || mediaBusy) {
      throw StateError('Wait for the current operation.');
    }
    validateDraft(d, audience, consent, window);
    final run = SendRun(
      name: d.name.trim().isEmpty
          ? t('رسالة بدون اسم', 'Untitled message')
          : d.name.trim(),
      sender: settings.sender,
      accountSid: settings.accountSid,
      draft: d.copy(),
      contacts: audience.map((c) => Contact.fromJson(c.toJson())).toList(),
    );
    runs.insert(0, run);
    try {
      await save();
    } catch (_) {
      runs.remove(run);
      rethrow;
    }
    notifyListeners();
    return run;
  }

  void pause() {
    paused = true;
    notifyListeners();
  }

  Future<void> process(
    SendRun run, {
    Duration interval = const Duration(seconds: 1),
  }) async {
    if (sending || mediaBusy) return;
    if (settings.sender != run.sender ||
        settings.accountSid != run.accountSid) {
      throw StateError(
        t(
          'حساب المرسل تغير. أنشئ إرسالاً جديداً',
          'Sender account changed. Create a new send.',
        ),
      );
    }
    final credentials = settings.copy();
    sending = true;
    paused = false;
    activeRun = run;
    error = null;
    notifyListeners();
    try {
      for (final c in run.contacts) {
        if (paused) break;
        if (run.attempts.containsKey(c.id)) continue;
        final latest = contacts.where((v) => v.id == c.id).firstOrNull;
        if (latest == null || !latest.consent) {
          run.attempts[c.id] = Attempt(
            contactId: c.id,
            status: 'canceled',
            error: t('الموافقة غير موجودة', 'Consent is no longer recorded'),
          );
          await save();
          notifyListeners();
          continue;
        }
        // Durable claim BEFORE any network request. Existing attempts never auto-retry.
        run.attempts[c.id] = Attempt(contactId: c.id);
        await save();
        notifyListeners();
        try {
          run.attempts[c.id] = await api.send(credentials, run, c);
        } on ApiFailure catch (e) {
          run.attempts[c.id] = Attempt(
            contactId: c.id,
            status: e.uncertain ? 'unknown' : 'failed',
            error: e.message,
            code: e.code,
          );
        } catch (_) {
          run.attempts[c.id] = Attempt(
            contactId: c.id,
            status: 'unknown',
            error: t(
              'افحص سجل Twilio قبل إعادة الإرسال',
              'Check Twilio logs before resending',
            ),
          );
        }
        await save();
        notifyListeners();
        final a = run.attempts[c.id]!;
        if (a.status == 'unknown' || a.code == '20003') {
          paused = true;
          break;
        }
        await Future<void>.delayed(interval);
      }
    } catch (e) {
      error = '$e';
      paused = true;
      rethrow;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> refresh(SendRun run) async {
    if (sending || refreshing) return;
    if (run.accountSid != settings.accountSid) {
      throw StateError(
        t(
          'اختر حساب Twilio المستخدم لهذا الإرسال',
          'Use the Twilio account for this send.',
        ),
      );
    }
    refreshing = true;
    notifyListeners();
    try {
      for (final a in run.attempts.values.toList()) {
        if (a.sid.isNotEmpty &&
            !['read', 'failed', 'undelivered', 'canceled'].contains(a.status)) {
          run.attempts[a.contactId] = await api.refresh(settings, a);
          await save();
          notifyListeners();
        }
      }
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }
}
