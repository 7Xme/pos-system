import 'package:bookstore_pos/core/barcode/barcode_scanner_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _digit(String d) {
  const keys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  return KeyDownEvent(
    timeStamp: Duration.zero,
    logicalKey: keys[int.parse(d)],
    physicalKey: PhysicalKeyboardKey.space,
    character: d,
  );
}

KeyDownEvent _enter() => KeyDownEvent(
      timeStamp: Duration.zero,
      logicalKey: LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
    );

void main() {
  setUp(() {
    BarcodeScannerService.captureEnabled = true;
    BarcodeScannerService.reset();
  });

  tearDown(() {
    BarcodeScannerService.captureEnabled = true;
    BarcodeScannerService.reset();
  });

  group('تمييز المسح عن الكتابة', () {
    test('مسح سريع + Enter يُلتقط ويُلتهم', () async {
      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      var consumed = 0;
      for (final ch in '100002'.split('')) {
        if (BarcodeScannerService.handleKey(_digit(ch))) consumed++;
      }
      final enterConsumed = BarcodeScannerService.handleKey(_enter());
      await Future.delayed(Duration.zero);

      expect(codes, ['100002']);
      expect(enterConsumed, true);
      expect(consumed, greaterThan(0)); // الأحرف المؤكدة التُهمت
      await sub.cancel();
    });

    test('كتابة بشرية بطيئة تمر دون التقاط', () async {
      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      var consumed = 0;
      for (final ch in '100002'.split('')) {
        if (BarcodeScannerService.handleKey(_digit(ch))) consumed++;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final enterConsumed = BarcodeScannerService.handleKey(_enter());
      await Future.delayed(Duration.zero);

      expect(codes, isEmpty);
      expect(consumed, 0);
      expect(enterConsumed, false);
      await sub.cancel();
    });

    test('كود قصير لا يُلتقط', () async {
      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      for (final ch in '12'.split('')) {
        BarcodeScannerService.handleKey(_digit(ch));
      }
      BarcodeScannerService.handleKey(_enter());
      await Future.delayed(Duration.zero);

      expect(codes, isEmpty);
      await sub.cancel();
    });

    test('التقاط معطّل خارج شاشة البيع', () async {
      BarcodeScannerService.captureEnabled = false;
      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      for (final ch in '100002'.split('')) {
        expect(BarcodeScannerService.handleKey(_digit(ch)), false);
      }
      expect(BarcodeScannerService.handleKey(_enter()), false);
      await Future.delayed(Duration.zero);

      expect(codes, isEmpty);
      await sub.cancel();
    });

    test('Enter وحيد (ليس مسحاً) يستدعي إتمام البيع ويُلتهم', () async {
      var calls = 0;
      BarcodeScannerService.onCheckoutHotkey = () => calls++;
      addTearDown(
        () => BarcodeScannerService.onCheckoutHotkey = null,
      );

      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      expect(BarcodeScannerService.handleKey(_enter()), true);
      await Future.delayed(Duration.zero);

      expect(calls, 1);
      expect(codes, isEmpty); // ليس مسحاً — لا صنف مضاف
      await sub.cancel();
    });

    test('المسح السريع لا يستدعي إتمام البيع', () async {
      var calls = 0;
      BarcodeScannerService.onCheckoutHotkey = () => calls++;
      addTearDown(
        () => BarcodeScannerService.onCheckoutHotkey = null,
      );

      final codes = <String>[];
      final sub = BarcodeScannerService.stream.listen(codes.add);

      for (final ch in '100002'.split('')) {
        BarcodeScannerService.handleKey(_digit(ch));
      }
      BarcodeScannerService.handleKey(_enter());
      await Future.delayed(Duration.zero);

      expect(codes, ['100002']);
      expect(calls, 0);
      await sub.cancel();
    });
  });
}
