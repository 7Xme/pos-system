import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// إيصال مرتجع مضغوط — A5 افتراضياً.
class PdfReturnBuilder {
  static Future<List<int>> build({
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
  }) async {
    final fonts = await loadArabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;
    final doc = pw.Document();

    pw.Widget rtl(pw.Widget child) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: child,
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: theme,
        footer: (ctx) => rtl(
          pw.Center(
            child: pw.Text(
              'إيصال مرتجع — $shopName',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ),
        build: (ctx) => [
          rtl(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    shopName,
                    style: pw.TextStyle(font: bold, fontSize: 15),
                  ),
                ),
                if (phone != null && phone.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      'هاتف: $phone',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'إيصال مرتجع',
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ),
                pw.Divider(thickness: 0.5, height: 8),
                pw.Text(
                  'رقم المرتجع: $returnNumber',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Text(
                  'عن الفاتورة: $invoiceNumber',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Text(
                  'التاريخ: ${date.year}/${date.month}/${date.day}'
                  ' — ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                if (cashier != null)
                  pw.Text(
                    'الكاشير: $cashier',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                if (reason.trim().isNotEmpty)
                  pw.Text(
                    'السبب: ${reason.trim()}',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          rtl(
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              headerAlignment: pw.Alignment.center,
              cellAlignment: pw.Alignment.center,
              cellPadding: const pw.EdgeInsets.symmetric(
                vertical: 2.5,
                horizontal: 4,
              ),
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
          ),
          pw.SizedBox(height: 8),
          rtl(
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(6),
                ),
              ),
              child: pw.Text(
                'إجمالي المرتجع: ${total.toStringAsFixed(2)} $currency',
                style: pw.TextStyle(font: bold, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }
}
