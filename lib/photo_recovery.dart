import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'controller.dart';
import 'domain.dart';

/// A published image is recoverable even when the public URL check fails.
class PhotoRecovery extends StatefulWidget {
  const PhotoRecovery({super.key, required this.c, required this.onVerified});
  final RelayController c;
  final void Function(String) onVerified;
  @override
  State<PhotoRecovery> createState() => _PhotoRecoveryState();
}

class _PhotoRecoveryState extends State<PhotoRecovery> {
  String progress = '', error = '';
  bool busy = false;
  RelayController get c => widget.c;
  Future<void> retry() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final url = await c.retryPhotoCheck(
        onProgress: (text) {
          if (mounted) setState(() => progress = text);
        },
      );
      if (mounted) widget.onVerified(url);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final s = c.settings;
      if (!s.lastPhotoPending ||
          s.mediaAccountSid != s.accountSid ||
          !isPublicHttps(s.lastPhotoUrl)) {
        return const SizedBox.shrink();
      }
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xfffff6df),
          border: Border.all(color: const Color(0xffebd9ab)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.t(
                'رابط الصورة محفوظ — لا حاجة لإعادة الرفع',
                'Photo link saved — no need to upload again',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              c.t(
                'قبل النشر تحقق التطبيق من اكتمال البناء، لكن الوصول العام للصورة لم يتأكد بعد. جرّب فتح الرابط ثم إعادة التحقق.',
                'The image was built and a deployment was requested, but public access is not verified yet. Try opening the link, then retry verification.',
              ),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(s.lastPhotoUrl),
            ),
            if (s.lastPhotoError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(s.lastPhotoError),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || c.mediaBusy || c.sending ? null : retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    c.t(
                      'إعادة التحقق واستخدام الصورة',
                      'Retry check & use photo',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: s.lastPhotoUrl),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(c.t('تم نسخ الرابط', 'Link copied')),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(c.t('نسخ الرابط', 'Copy link')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      if (!await launchUrl(
                        Uri.parse(s.lastPhotoUrl),
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError('Unable to open link');
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = c.t(
                            'تعذر فتح المتصفح. انسخ الرابط وافتحه يدوياً.',
                            'Unable to open the browser. Copy the link and open it manually.',
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(c.t('فتح الصورة', 'Open photo')),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              Text(progress),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      );
    },
  );
}
