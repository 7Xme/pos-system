import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

/// نطق عربي عبر الإنترنت (صوت Google) — بديل SAPI عند غياب أصوات ويندوز.
///
/// لا يرمي استثناءً أبداً: أي عطل (لا إنترنت، حجب الخدمة، مشكلة المشغل)
/// يُرجع false بهدوء. الجلب والتشغيل منفصلان لاختبار الجلب دون صوت.
class OnlineTtsService {
  OnlineTtsService._();
  static final OnlineTtsService instance = OnlineTtsService._();

  AudioPlayer? _player;

  /// يجلب MP3 لنص قصير (حتى ~180 حرفاً). client اختياري لحقن عميل وهمي.
  static Future<Uint8List?> fetchAudio(
    String text, {
    http.Client? client,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final owned = client == null;
    final c = client ?? http.Client();
    try {
      final uri = Uri.https('translate.google.com', '/translate_tts', {
        'client': 'tw-ob',
        'tl': 'ar',
        'ie': 'UTF-8',
        'q': t.length > 180 ? t.substring(0, 180) : t,
      });
      final resp = await c.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    } finally {
      if (owned) c.close();
    }
  }

  /// يجلب ثم يشغّل. يُرجع true عند بدء التشغيل بنجاح.
  Future<bool> speak(String text) async {
    try {
      final bytes = await fetchAudio(text);
      if (bytes == null || bytes.isEmpty) return false;
      _player ??= AudioPlayer();
      try {
        await _player!.stop();
      } catch (_) {
        // تجاهل — قد لا يكون هناك ما يُوقف
      }
      await _player!.play(BytesSource(bytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // تجاهل — الإيقاف اختياري
    }
  }
}
