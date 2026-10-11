import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// سطر في قائمة المشتريات / أمر الشراء.
class PurchaseLine {
  final String name;
  final String barcode;
  final int qty;
  final double unitCost;
  const PurchaseLine({
    required this.name,
    required this.barcode,
    required this.qty,
    required this.unitCost,
  });
  double get total => qty * unitCost;
}

/// قائمة مشتريات / أمر شراء A4 عربي — للطباعة وأخذها للمورد.
class PdfPurchaseBuilder {
  static Future<List<int>> build({
    required String shopName,
    required String poNumber,
    required DateTime date,
    required List<PurchaseLine> lines,
    String currency = 'درهم',
    String? phone,
    List<int>? logoBytes,
    String supplierName = '',
    String? supplierPhone,
  }) async {
    final fonts = await loadArabicFonts();
    final theme = fonts.theme;
    final bold = fonts.bold;

    final total = lines.fold<double>(0, (s, e) => s + e.total);
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
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
                  'أمر شراء / قائمة مشتريات',
                  style: pw.TextStyle(font: bold, fontSize: 16),
                ),
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الرقم: $poNumber'),
                  pw.Text(
                    'التاريخ: ${date.year}/${date.month}/${date.day}',
                  ),
                ],
              ),
              if (supplierName.isNotEmpty)
                pw.Text('المورد: $supplierName'),
              if (supplierPhone != null && supplierPhone.isNotEmpty)
                pw.Text('هاتف المورد: $supplierPhone'),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: bold, fontSize: 12),
                cellStyle: const pw.TextStyle(fontSize: 11),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.center,
                headers: const [
                  'الإجمالي',
                  'سعر الوحدة',
                  'الكمية',
                  'الباركود',
                  'الصنف',
                ],
                data: [
                  for (final l in lines)
                    [
                      l.total.toStringAsFixed(2),
                      l.unitCost.toStringAsFixed(2),
                      l.qty.toString(),
                      l.barcode,
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
                child: pw.Text(
                  'إجمالي التكلفة التقديرية: '
                  '${total.toStringAsFixed(2)} $currency',
                  style: pw.TextStyle(font: bold, fontSize: 16),
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text('توقيع المستلم: ................'),
                  pw.Text('توقيع المورد: ................'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }
}
