import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// الخطوة 5 (أ): توليد فاتورة A4 عربية بسيطة — مجموع فقط (حسب اختيارك)
/// الخط مدمج في التطبيق (assets/fonts) — يعمل دون إنترنت.
class InvoiceLine {
  final String name;
  final int qty;
  final double unitPrice;
  const InvoiceLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });
  double get total => qty * unitPrice;
}

/// تحميل خط Cairo المدمج — نستخدم نفس الملف للعادي والعريض
/// (الخط المتغير يُرسم بوزنه الافتراضي داخل PDF).
Future<({pw.Font base, pw.Font bold, pw.ThemeData theme})>
    _arabicFonts() async {
  final data = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
  final base = pw.Font.ttf(data);
  final bold = pw.Font.ttf(data);
  return (
    base: base,
    bold: bold,
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
}

class PdfInvoiceBuilder {
  static Future<List<int>> build({
    required String shopName,
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceLine> lines,
    required double amountPaid,
    String? cashier,
    String? notes,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
  }) async {
    final fonts = await _arabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;

    final total = lines.fold<double>(0, (s, e) => s + e.total);
    final change = amountPaid - total;

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        // حزمة pdf ترسم LTR؛ نحاكي RTL بمحاذاة يمين + ترتيب أعمدة معكوس
        build: (ctx) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logoBytes != null)
                pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(Uint8List.fromList(logoBytes)),
                    width: 90,
                    height: 90,
                  ),
                ),
              if (logoBytes != null) pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  shopName,
                  style: pw.TextStyle(font: bold, fontSize: 22),
                ),
              ),
              if (phone != null && phone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'هاتف: $phone',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'مكتبة وأدوات مدرسية — فاتورة بيع',
                  style: const pw.TextStyle(fontSize: 13),
                ),
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('رقم الفاتورة: $invoiceNumber'),
                  pw.Text(
                    'التاريخ: ${date.year}/${date.month}/${date.day}'
                    ' — ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                ],
              ),
              if (cashier != null) pw.Text('الكاشير: $cashier'),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: bold, fontSize: 12),
                cellStyle: const pw.TextStyle(fontSize: 11),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.center,
                headers: const ['الإجمالي', 'السعر', 'الكمية', 'الصنف'],
                data: [
                  for (final l in lines)
                    [
                      l.total.toStringAsFixed(2),
                      l.unitPrice.toStringAsFixed(2),
                      l.qty.toString(),
                      l.name,
                    ],
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      'الإجمالي: ${total.toStringAsFixed(2)} $currency',
                      style: pw.TextStyle(font: bold, fontSize: 16),
                    ),
                    pw.Text(
                      'المدفوع: ${amountPaid.toStringAsFixed(2)}'
                      ' — الباقي: ${change.toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
              if (notes != null && notes.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('ملاحظات: $notes'),
              ],
              pw.Spacer(),
              pw.Center(
                child: pw.Text(
                  'شكراً لتسوقكم معنا — نتمنى لكم عاماً دراسياً موفقاً',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }
}

/// الخطوة 5 (ب): ملصقات باركود — ورقة A4 مقسمة 3 أعمدة
class BarcodeLabelBuilder {
  static Future<List<int>> buildSheet({
    required List<({String name, String barcode, double price})> items,
    String currency = 'درهم',
  }) async {
    final fonts = await _arabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;
    final doc = pw.Document();

    const cols = 3;
    final rows = (items.length / cols).ceil();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        theme: theme,
        build: (ctx) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            children: [
              for (var r = 0; r < rows; r++)
                pw.Expanded(
                  child: pw.Row(
                    children: [
                      for (var c = 0; c < cols; c++)
                        pw.Expanded(
                          child: _label(
                            r * cols + c < items.length
                                ? items[r * cols + c]
                                : null,
                            bold,
                            currency,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _label(
    ({String name, String barcode, double price})? item,
    pw.Font bold,
    String currency,
  ) {
    if (item == null) return pw.Container();
    return pw.Container(
      margin: const pw.EdgeInsets.all(4),
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item.name,
            style: pw.TextStyle(font: bold, fontSize: 10),
            maxLines: 1,
          ),
          pw.Text(
            '${item.price.toStringAsFixed(2)} $currency',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 4),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: item.barcode,
            height: 40,
          ),
          pw.Text(item.barcode, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }
}
