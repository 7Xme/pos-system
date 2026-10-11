import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_builders.dart';

/// طباعة A4 عادية (حسب اختيارك — بدون طابعة حرارية)
class A4PrintService {
  /// معاينة + طباعة فاتورة
  static Future<void> printInvoice({
    required String shopName,
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceLine> lines,
    required double amountPaid,
    String? cashier,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
  }) async {
    final bytes = await PdfInvoiceBuilder.build(
      shopName: shopName,
      invoiceNumber: invoiceNumber,
      date: date,
      lines: lines,
      amountPaid: amountPaid,
      cashier: cashier,
      currency: currency,
      phone: phone,
      logoBytes: logoBytes,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(bytes),
      name: invoiceNumber,
    );
  }

  /// طباعة شيت ملصقات باركود
  static Future<void> printBarcodeSheet(
    List<({String name, String barcode, double price})> items, {
    String currency = 'درهم',
  }) async {
    final bytes = await BarcodeLabelBuilder.buildSheet(
      items: items,
      currency: currency,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(bytes),
      name: 'barcode-labels',
    );
  }
}
