import 'dart:convert';

import 'package:bookstore_pos/core/printing/pdf_builders.dart';
import 'package:pdf/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// يستخرج أبعاد الصفحة (عرض × ارتفاع بالنقاط) من /MediaBox في ملف PDF.
List<double> _mediaBoxOf(List<int> bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final m =
      RegExp(r'/MediaBox\s*\[([^\]]+)\]').firstMatch(raw);
  expect(m, isNotNull, reason: 'لا توجد MediaBox في PDF');
  final nums =
      m!.group(1)!.split(RegExp(r'\s+')).map(double.parse).toList();
  expect(nums.length, 4);
  return [nums[2] - nums[0], nums[3] - nums[1]];
}

void main() {
  group('فاتورة PDF', () {
    testWidgets('تُبنى بالشعار والهاتف والعملة', (tester) async {
      // PNG شفاف 1×1 صالح
      final logo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      final bytes = await PdfInvoiceBuilder.build(
        shopName: 'مكتبة النجاح',
        invoiceNumber: 'INV-TEST-1',
        date: DateTime(2026, 10, 10, 14, 30),
        lines: const [
          InvoiceLine(name: 'قلم جاف أزرق', qty: 2, unitPrice: 8),
          InvoiceLine(name: 'كراسة 100 ورقة', qty: 1, unitPrice: 25),
        ],
        amountPaid: 50,
        cashier: 'كاشير',
        currency: 'درهم',
        phone: '0612345678',
        logoBytes: logo,
      );
      expect(bytes.isNotEmpty, true);
      // ملف PDF يبدأ بـ %PDF
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('تُبنى بدون شعار وهاتف', (tester) async {
      final bytes = await PdfInvoiceBuilder.build(
        shopName: 'مكتبة النجاح',
        invoiceNumber: 'INV-TEST-2',
        date: DateTime(2026, 10, 10),
        lines: const [],
        amountPaid: 0,
      );
      expect(bytes.isNotEmpty, true);
    });

    testWidgets('مقاس الصفحة: A5 افتراضياً وA4 عند الطلب',
        (tester) async {
      // الافتراضي A5 (419.53 × 595.28 نقطة) — دون تمرير المقاس
      final def = _mediaBoxOf(
        await PdfInvoiceBuilder.build(
          shopName: 'مكتبة النجاح',
          invoiceNumber: 'INV-SIZE',
          date: DateTime(2026, 10, 12),
          lines: const [
            InvoiceLine(name: 'قلم', qty: 1, unitPrice: 8),
          ],
          amountPaid: 8,
        ),
      );
      expect(def[0], moreOrLessEquals(419.53, epsilon: 0.5));
      expect(def[1], moreOrLessEquals(595.28, epsilon: 0.5));

      // A4 عند الطلب (595.28 × 841.89 نقطة)
      final a4 = _mediaBoxOf(
        await PdfInvoiceBuilder.build(
          shopName: 'مكتبة النجاح',
          invoiceNumber: 'INV-SIZE-A4',
          date: DateTime(2026, 10, 12),
          lines: const [
            InvoiceLine(name: 'قلم', qty: 1, unitPrice: 8),
          ],
          amountPaid: 8,
          pageFormat: PdfPageFormat.a4,
        ),
      );
      expect(a4[0], moreOrLessEquals(595.28, epsilon: 0.5));
      expect(a4[1], moreOrLessEquals(841.89, epsilon: 0.5));
    });

    testWidgets('فاتورة طويلة (60 صنفاً) تُبنى دون عطل على A5',
        (tester) async {
      final bytes = await PdfInvoiceBuilder.build(
        shopName: 'مكتبة النجاح',
        invoiceNumber: 'INV-LONG',
        date: DateTime(2026, 10, 12),
        lines: [
          for (var i = 1; i <= 60; i++)
            InvoiceLine(name: 'صنف $i', qty: i, unitPrice: 5.0 + i),
        ],
        amountPaid: 100000,
        discount: 50,
      );
      expect(bytes.isNotEmpty, true);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final box = _mediaBoxOf(bytes);
      expect(box[0], moreOrLessEquals(419.53, epsilon: 0.5));
      expect(box[1], moreOrLessEquals(595.28, epsilon: 0.5));
    });

    testWidgets('ملصقات الباركود تُبنى بالعملة', (tester) async {
      final bytes = await BarcodeLabelBuilder.buildSheet(
        items: const [
          (name: 'قلم', barcode: '100002', price: 8),
        ],
        currency: 'درهم',
      );
      expect(bytes.isNotEmpty, true);
    });
  });
}
