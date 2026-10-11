import 'dart:convert';

import 'package:bookstore_pos/core/printing/pdf_builders.dart';
import 'package:flutter_test/flutter_test.dart';

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
