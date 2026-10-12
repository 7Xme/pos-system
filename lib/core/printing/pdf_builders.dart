import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// الخطوة 5 (أ): توليد فاتورة عربية بسيطة — مجموع فقط (حسب اختيارك)
/// حجم الورق A5 افتراضياً (قابل للتبديل إلى A4 من الإعدادات).
/// الخط مدمج في التطبيق (assets/fonts) — يعمل دون إنترنت.
class InvoiceLine {  final String name;
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
class PdfInvoiceBuilder {
  static Future<List<int>> build({
    required String shopName,
    required String invoiceNumber,
    required DateTime date,
    required List<InvoiceLine> lines,
    required double amountPaid,
    double discount = 0,
    String? discountLabel,
    String? cashier,
    String? notes,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
  }) async {
    final fonts = await loadArabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;

    final subtotal = lines.fold<double>(0, (s, e) => s + e.total);
    final total = subtotal - (discount < 0 ? 0 : discount);
    final change = amountPaid - (total < 0 ? 0 : total);

    final doc = pw.Document();

    // MultiPage: الجدول يمتد على عدة صفحات عند كثرة الأصناف،
    // والخطوط صغيرة ومضغوطة لاستيعاب أكبر عدد في نفس الورقة.
    // حزمة pdf ترسم LTR؛ نحاكي RTL بمحاذاة يمين + ترتيب أعمدة معكوس.
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
              'شكراً لتسوقكم معنا — نتمنى لكم عاماً دراسياً موفقاً',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ),
        build: (ctx) => [
          rtl(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (logoBytes != null)
                  pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(Uint8List.fromList(logoBytes)),
                      width: 54,
                      height: 54,
                    ),
                  ),
                if (logoBytes != null) pw.SizedBox(height: 2),
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
                    'مكتبة وأدوات مدرسية — فاتورة بيع',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.Divider(thickness: 0.5, height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم الفاتورة: $invoiceNumber',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                    pw.Text(
                      'التاريخ: ${date.year}/${date.month}/${date.day}'
                      ' — ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ],
                ),
                if (cashier != null)
                  pw.Text(
                    'الكاشير: $cashier',
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
              columnWidths: {
                // الصنف أوسع عمود (معكوس RTL: آخر عمود يظهر أولاً يميناً)
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(1.6),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(2.6),
              },
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
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (discount > 0) ...[
                    pw.Text(
                      'المجموع الفرعي: ${subtotal.toStringAsFixed(2)} $currency',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                    pw.Text(
                      'الخصم${discountLabel == null ? '' : ' ($discountLabel)'}: '
                      '-${discount.toStringAsFixed(2)} $currency',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                    pw.SizedBox(height: 2),
                  ],
                  pw.Text(
                    'الإجمالي: ${(total < 0 ? 0 : total).toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: bold, fontSize: 12.5),
                  ),
                  pw.Text(
                    'المدفوع: ${amountPaid.toStringAsFixed(2)}'
                    ' — الباقي: ${change.toStringAsFixed(2)}',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ],
              ),
            ),
          ),
          if (notes != null && notes.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            rtl(
              pw.Text(
                'ملاحظات: $notes',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
          ],
        ],
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
    final fonts = await loadArabicFonts();
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
