import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// خط Cairo المدمج مشترك لكل مستندات PDF (يعمل دون إنترنت).
/// ملاحظة: الخط المتغير يُرسم بوزنه الافتراضي داخل PDF.
Future<({pw.Font base, pw.Font bold, pw.ThemeData theme})>
    loadArabicFonts() async {
  final data = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
  final base = pw.Font.ttf(data);
  final bold = pw.Font.ttf(data);
  return (
    base: base,
    bold: bold,
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
}
