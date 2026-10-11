import 'package:bookstore_pos/core/printing/pdf_purchase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('أمر الشراء PDF', () {
    testWidgets('يُبنى بالشعار والهاتف والمورد', (tester) async {
      final bytes = await PdfPurchaseBuilder.build(
        shopName: 'مكتبة النجاح',
        poNumber: 'PO-TEST-1',
        date: DateTime(2026, 10, 10),
        lines: const [
          PurchaseLine(name: 'قلم جاف', barcode: '901', qty: 10, unitCost: 5),
          PurchaseLine(name: 'كراسة', barcode: '902', qty: 20, unitCost: 18),
        ],
        currency: 'درهم',
        phone: '0612345678',
        supplierName: 'مورد الجملة',
        supplierPhone: '0699',
      );
      expect(bytes.isNotEmpty, true);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('يُبنى بقائمة فارغة دون تعطل', (tester) async {
      final bytes = await PdfPurchaseBuilder.build(
        shopName: 'مكتبة',
        poNumber: 'PO-EMPTY',
        date: DateTime(2026, 10, 10),
        lines: const [],
      );
      expect(bytes.isNotEmpty, true);
    });
  });
}
