import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'domain.dart';

class PhotoCheckFailure implements Exception {
  PhotoCheckFailure(this.url, this.detail);
  final String url, detail;
  @override
  String toString() =>
      'لم نستطع التحقق من الصورة. الرابط محفوظ؛ أعد التحقق دون رفعها مجدداً. / Could not verify the photo. Its link is saved; retry verification without uploading again.\n$detail\n$url';
}

/// Reads actual image bytes. HEAD alone does not prove a URL serves a photo.
class PublicPhotoProbe {
  PublicPhotoProbe(
    this.client, {
    this.attempts = 30,
    this.interval = const Duration(seconds: 2),
    this.budget = const Duration(seconds: 90),
    this.requestTimeout = const Duration(seconds: 10),
  });
  final http.Client client;
  final int attempts;
  final Duration interval, budget, requestTimeout;

  Future<String> verify(
    String url, {
    void Function(String)? onProgress,
    String language = 'ar',
  }) async {
    if (!isPublicHttps(url)) {
      throw PhotoCheckFailure(url, 'Use a public HTTPS image URL.');
    }
    final watch = Stopwatch()..start();
    var detail = 'لم يصل رد / No response';
    for (var n = 0; n < attempts && watch.elapsed < budget; n++) {
      onProgress?.call(
        language == 'en'
            ? 'Checking photo link (${n + 1}/$attempts)…'
            : 'التحقق من رابط الصورة (${n + 1}/$attempts)…',
      );
      try {
        var target = Uri.parse(url);
        for (var hop = 0; hop <= 3; hop++) {
          final remaining = budget - watch.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException('Photo check deadline');
          }
          final timeout = remaining < requestTimeout
              ? remaining
              : requestTimeout;
          // Public GETs and redirects must never contain Twilio credentials.
          final response = await client
              .send(http.Request('GET', target)..followRedirects = false)
              .timeout(timeout);
          final reader = StreamIterator<List<int>>(response.stream);
          try {
            final code = response.statusCode;
            if ([301, 302, 303, 307, 308].contains(code)) {
              final location = response.headers['location'];
              if (location == null || hop == 3) {
                detail = 'HTTP $code — invalid or excessive redirects';
                break;
              }
              final next = target.resolve(location);
              if (!isPublicHttps(next.toString())) {
                detail = 'Image redirected to a non-public HTTPS URL';
                break;
              }
              target = next;
              continue;
            }
            final type = (response.headers['content-type'] ?? '')
                .split(';')
                .first
                .trim()
                .toLowerCase();
            detail =
                'HTTP $code · Content-Type: ${type.isEmpty ? 'missing' : type}';
            if (code != 200) break;
            if (response.contentLength != null &&
                response.contentLength! > 5 * 1024 * 1024) {
              detail = '$detail · exceeds 5 MB';
              break;
            }
            final prefix = BytesBuilder(copy: false);
            while (prefix.length < 8 &&
                await reader.moveNext().timeout(timeout)) {
              prefix.add(reader.current);
            }
            final bytes = prefix.takeBytes();
            final jpg =
                bytes.length >= 3 &&
                bytes[0] == 255 &&
                bytes[1] == 216 &&
                bytes[2] == 255;
            final png =
                bytes.length >= 8 &&
                bytes[0] == 137 &&
                bytes[1] == 80 &&
                bytes[2] == 78 &&
                bytes[3] == 71 &&
                bytes[4] == 13 &&
                bytes[5] == 10 &&
                bytes[6] == 26 &&
                bytes[7] == 10;
            if ((jpg && type == 'image/jpeg') || (png && type == 'image/png')) {
              return url;
            }
            detail =
                '$detail · ${png || jpg ? 'image MIME type does not match' : 'response is not a JPG or PNG image'}';
          } finally {
            await reader.cancel();
          }
          break;
        }
      } on TimeoutException {
        detail = 'انتهت مهلة الاتصال برابط الصورة / Image connection timed out';
      } on SocketException {
        detail = 'تعذر الاتصال بنطاق الصورة أو العثور عليه DNS / Image host could not be reached or resolved (DNS)';
      } on HandshakeException {
        detail = 'تعذر التحقق من اتصال HTTPS للصورة / Image HTTPS certificate or TLS connection failed';
      } catch (e) {
        detail = 'تعذر قراءة الصورة / Image request failed (${e.runtimeType})';
      }
      if (n + 1 < attempts && watch.elapsed + interval < budget) {
        await Future<void>.delayed(interval);
      }
    }
    throw PhotoCheckFailure(url, detail);
  }
}
