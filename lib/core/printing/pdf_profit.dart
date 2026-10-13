import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// تقرير الأرباح — مضغوط، A5 افتراضياً.
/// ملاحظة: الأسطر بلا تكلفة مسجلة (فواتير ما قبل v4) مستبعدة من التكلفة
/// وتُعرض في noCostLines — بلا أي تقدير.
class PdfProfitBuilder {
  static Future<List<int>> build({
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
  }) async {
    final fonts = await loadArabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;
    final doc = pw.Document();

    final netRevenue = revenue - refunds;
    final netCogs = cogs - cogsReturned;
    final profit = netRevenue - netCogs;
    final margin = netRevenue <= 0 ? 0.0 : profit / netRevenue * 100;

    pw.Widget rtl(pw.Widget child) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: child,
        );

    String money(double v) => '${v.toStringAsFixed(2)} $currency';

    pw.Widget row(String label, String value, {bool big = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: big ? bold : null,
                  fontSize: big ? 12 : 9.5,
                ),
              ),
              pw.Text(
                label,
                style: pw.TextStyle(
                  font: big ? bold : null,
                  fontSize: big ? 12 : 9.5,
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        theme: theme,
        footer: (ctx) => rtl(
          pw.Center(
            child: pw.Text(
              'تقرير الأرباح — $shopName',
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
                    'تقرير الأرباح — $scopeLabel',
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ),
                pw.Divider(thickness: 0.5, height: 8),
                row('إيراد المبيعات:', money(revenue)),
                row('المردودات:', '-${money(refunds)}'),
                row('صافي الإيراد:', money(netRevenue), big: true),
                row('تكلفة المباع:', '-${money(netCogs)}'),
                row('الربح الإجمالي:', money(profit), big: true),
                row('الهامش:', '${margin.toStringAsFixed(1)}%'),
                if (noCostLines > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'ملاحظة: $noCostLines سطر بلا تكلفة مسجلة '
                    '(فواتير قبل التحديث) — مستبعدة من التكلفة.',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
                if (top.isNotEmpty) ...[
                  pw.Divider(thickness: 0.5, height: 8),
                  pw.Text(
                    'الأعلى ربحاً:',
                    style: pw.TextStyle(font: bold, fontSize: 10),
                  ),
                  pw.SizedBox(height: 4),
                ],
              ],
            ),
          ),
          if (top.isNotEmpty)
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
                headers: const ['الربح', 'الكمية', 'الصنف'],
                data: [
                  for (final t in top)
                    [
                      t.profit.toStringAsFixed(2),
                      t.qty.toString(),
                      t.name,
                    ],
                ],
              ),
            ),
        ],
      ),
    );

    return doc.save();
  }
}
