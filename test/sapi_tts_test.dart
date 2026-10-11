import 'package:bookstore_pos/core/tts/arabic_tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArabicTtsService (SAPI FFI)', () {
    test('speak لا يرمي استثناء أبداً ويُرجع bool', () async {
      final ok = await ArabicTtsService.instance.speak('اختبار');
      expect(ok, isA<bool>());
    });

    test('speakTotal لا يرمي استثناء أبداً', () async {
      await ArabicTtsService.instance.speakTotal(85.5);
    });

    test('stop لا يرمي استثناء أبداً', () async {
      await ArabicTtsService.instance.stop();
    });

    test('diagnose لا يرمي استثناء ويُرجع تقريراً', () async {
      final d = await ArabicTtsService.instance.diagnose();
      expect(d.voices, isA<List>());
      expect(d.arabicCount, greaterThanOrEqualTo(0));
      // في هذه البيئة SAPI معطل — يجب أن يفشل بأدب لا بتعطل
      expect(d.speakOk, isA<bool>());
    });
  });
}
