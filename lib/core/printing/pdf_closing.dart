import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// ملخص الإغلاق اليومي (Z-report) — مضغوط، A5 افتراضياً.
class ClosingSummaryData {
  final int invoiceCount;
  final double gross;
  final double discount;
  final double net;
  final double paid;
  final double change;
  final int itemsSold;
  final List<({String name, int qty, double total})> top;

  /// نطاق التقرير (اليوم / تاريخ / من…إلى / كل السجل).
  final String scopeLabel;

  /// إجمالي المردودات في النطاق (0 = لا سطر إضافي).
  final double returnsTotal;

  const ClosingSummaryData({
    required this.invoiceCount,
    required this.gross,
    required this.discount,
    required this.net,
    required this.paid,
    required this.change,
    required this.itemsSold,
    this.top = const [],
    this.scopeLabel = 'اليوم',
    this.returnsTotal = 0,
  });

  double get netAfterReturns => net - returnsTotal;
}

class PdfClosingBuilder {
  static Future<List<int>> build({
    required String shopName,
    required DateTime date,
    required ClosingSummaryData summary,
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
              'تقرير إغلاق — $shopName',
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
                    'تقرير الإغلاق — ${summary.scopeLabel}',
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ),
                pw.Divider(thickness: 0.5, height: 8),
                row('عدد الفواتير:', '${summary.invoiceCount}'),
                row('الأصناف المباعة:', '${summary.itemsSold}'),
                row('الإجمالي الخام:', money(summary.gross)),
                row('الخصومات:', '-${money(summary.discount)}'),
                row(
                  'الصافي:',
                  money(summary.net < 0 ? 0 : summary.net),
                  big: true,
                ),
                if (summary.returnsTotal > 0) ...[
                  row(
                    'المرتجعات:',
                    '-${money(summary.returnsTotal)}',
                  ),
                  row(
                    'الصافي بعد المرتجعات:',
                    money(summary.netAfterReturns),
                    big: true,
                  ),
                ],
                row('المدفوع:', money(summary.paid)),
                row('الباقي للزبائن:', money(summary.change)),
                if (summary.top.isNotEmpty) ...[
                  pw.Divider(thickness: 0.5, height: 8),
                  pw.Text(
                    'الأعلى مبيعاً:',
                    style: pw.TextStyle(font: bold, fontSize: 10),
                  ),
                  pw.SizedBox(height: 4),
                ],
              ],
            ),
          ),
          if (summary.top.isNotEmpty)
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
                headers: const ['الإجمالي', 'الكمية', 'الصنف'],
                data: [
                  for (final t in summary.top)
                    [
                      t.total.toStringAsFixed(2),
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
