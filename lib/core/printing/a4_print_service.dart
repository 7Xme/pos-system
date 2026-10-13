import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'pdf_builders.dart';
import 'pdf_closing.dart';
import 'pdf_profit.dart';
import 'pdf_purchase.dart';
import 'pdf_return.dart';

/// طباعة الفواتير (A5 افتراضياً — قابل للتبديل من الإعدادات)
/// وملصقات الباركود وأوامر الشراء (A4) — بدون طابعة حرارية.
/// يُحوّل نص الإعداد ('a5'/'a4') إلى مقاس عبر [paperFormatOf].
class A4PrintService {
  static PdfPageFormat paperFormatOf(String paperSize) =>
      paperSize == 'a4' ? PdfPageFormat.a4 : PdfPageFormat.a5;

  /// إرسال مستند للطباعة: مباشرةً على الطابعة المحددة بلا حوار، مع رجوع
  /// تلقائي إلى حوار الطباعة عند غياب الطابعة أو فشل الطباعة المباشرة
  /// (لا تُفقد أي مطبوعة).
  static Future<void> _send({
    required List<int> bytes,
    required String name,
    required PdfPageFormat format,
    required bool direct,
    String? printerName,
  }) async {
    if (direct) {
      try {
        final printers = await Printing.listPrinters();
        Printer? match;
        for (final p in printers) {
          if (p.isDefault) {
            match = p;
            break;
          }
        }
        if (printerName != null) {
          match = null;
          for (final p in printers) {
            if (p.name == printerName) {
              match = p;
              break;
            }
          }
        }
        if (match != null) {
          final done = await Printing.directPrintPdf(
            printer: match,
            onLayout: (_) async => Uint8List.fromList(bytes),
            name: name,
            format: format,
          );
          if (done) return;
        }
      } catch (_) {
        // أي عطل هنا يرجوع إلى حوار الطباعة
      }
    }
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(bytes),
      name: name,
      // يظهر هذا المقاس تلقائياً في حوار الطباعة دون تغيير يدوي.
      format: format,
    );
  }

  /// معاينة + طباعة فاتورة
  static Future<void> printInvoice({
    required String shopName,
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceLine> lines,
    required double amountPaid,
    double discount = 0,
    String? discountLabel,
    String? cashier,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await PdfInvoiceBuilder.build(
      shopName: shopName,
      invoiceNumber: invoiceNumber,
      date: date,
      lines: lines,
      amountPaid: amountPaid,
      discount: discount,
      discountLabel: discountLabel,
      cashier: cashier,
      currency: currency,
      phone: phone,
      logoBytes: logoBytes,
      pageFormat: pageFormat,
    );
    await _send(
      bytes: bytes,
      name: invoiceNumber,
      format: pageFormat,
      direct: direct,
      printerName: printerName,
    );
  }

  /// طباعة شيت ملصقات باركود
  static Future<void> printBarcodeSheet(
    List<({String name, String barcode, double price})> items, {
    String currency = 'درهم',
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await BarcodeLabelBuilder.buildSheet(
      items: items,
      currency: currency,
    );
    await _send(
      bytes: bytes,
      name: 'barcode-labels',
      format: PdfPageFormat.a4,
      direct: direct,
      printerName: printerName,
    );
  }

  /// طباعة تقرير الإغلاق اليومي
  static Future<void> printClosing({
    required String shopName,
    required DateTime date,
    required ClosingSummaryData summary,
    String currency = 'درهم',
    String? phone,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await PdfClosingBuilder.build(
      shopName: shopName,
      date: date,
      summary: summary,
      currency: currency,
      phone: phone,
      pageFormat: pageFormat,
    );
    await _send(
      bytes: bytes,
      name: 'closing-${date.year}${date.month}${date.day}',
      format: pageFormat,
      direct: direct,
      printerName: printerName,
    );
  }

  /// طباعة إيصال مرتجع
  static Future<void> printReturn({
    required String shopName,
    required String returnNumber,
    required String invoiceNumber,
    required DateTime date,
    required List<({String name, int qty, double unitPrice, double total})>
        lines,
    required double total,
    String reason = '',
    String? cashier,
    String currency = 'درهم',
    String? phone,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await PdfReturnBuilder.build(
      shopName: shopName,
      returnNumber: returnNumber,
      invoiceNumber: invoiceNumber,
      date: date,
      lines: lines,
      total: total,
      reason: reason,
      cashier: cashier,
      currency: currency,
      phone: phone,
      pageFormat: pageFormat,
    );
    await _send(
      bytes: bytes,
      name: returnNumber,
      format: pageFormat,
      direct: direct,
      printerName: printerName,
    );
  }

  /// طباعة تقرير الأرباح
  static Future<void> printProfit({
    required String shopName,
    required String scopeLabel,
    required double revenue,
    required double refunds,
    required double cogs,
    required double cogsReturned,
    required int noCostLines,
    required List<({String name, int qty, double profit})> top,
    String currency = 'درهم',
    String? phone,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await PdfProfitBuilder.build(
      shopName: shopName,
      scopeLabel: scopeLabel,
      revenue: revenue,
      refunds: refunds,
      cogs: cogs,
      cogsReturned: cogsReturned,
      noCostLines: noCostLines,
      top: top,
      currency: currency,
      phone: phone,
      pageFormat: pageFormat,
    );
    await _send(
      bytes: bytes,
      name: 'profit-$scopeLabel',
      format: pageFormat,
      direct: direct,
      printerName: printerName,
    );
  }

  /// طباعة قائمة مشتريات / أمر شراء
  static Future<void> printPurchaseOrder({
    required String shopName,
    required String poNumber,
    required DateTime date,
    required List<PurchaseLine> lines,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
    String supplierName = '',
    String? supplierPhone,
    bool direct = false,
    String? printerName,
  }) async {
    final bytes = await PdfPurchaseBuilder.build(
      shopName: shopName,
      poNumber: poNumber,
      date: date,
      lines: lines,
      currency: currency,
      phone: phone,
      logoBytes: logoBytes,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
    );
    await _send(
      bytes: bytes,
      name: poNumber,
      format: PdfPageFormat.a4,
      direct: direct,
      printerName: printerName,
    );
  }
}
