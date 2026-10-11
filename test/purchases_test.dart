import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/features/purchases/bloc/purchases_bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('المشتريات', () {
    test('إضافة المنخفضة + حفظ + استلام يحدّث المخزون', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final cat = await db.insertCategory('قرطاسية');
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'قلم',
          barcode: '901',
          price: 8,
          cost: const Value(5),
          stockQty: const Value(2),
          minStock: const Value(10),
          categoryId: Value(cat),
        ),
      );

      final bloc = PurchasesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(PurchasesStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PurchasesState>(
            (s) => s.status == PurchasesStatus.ready,
          ),
        ),
      );

      // إضافة المنخفضة: الكمية المقترحة حتى ضعف الحد = 10*2-2 = 18
      bloc.add(PurchasesAddLowStock());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PurchasesState>((s) => s.draft.length == 1),
        ),
      );
      expect(bloc.state.draft.first.qty, 18);

      // حفظ الأمر
      bloc.add(const PurchasesSupplierChanged('مورد', '0600'));
      bloc.add(PurchasesSaveOrder());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PurchasesState>(
            (s) =>
                s.status == PurchasesStatus.ready &&
                s.draft.isEmpty &&
                s.saved.length == 1,
          ),
        ),
      );
      expect(bloc.state.saved.first.order.totalCost, 18 * 5);

      // الاستلام يزيد المخزون: 2 + 18 = 20
      final id = bloc.state.saved.first.order.id;
      bloc.add(PurchasesReceiveOrder(id));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PurchasesState>(
            (s) =>
                s.saved.isNotEmpty &&
                s.saved.first.order.status == 'received',
          ),
        ),
      );
      final items = await db.itemsOfOrder(id);
      final prod = await db.getProduct(items.first.productId);
      expect(prod?.stockQty, 20);
    });

    test('حفظ قائمة فارغة مرفوض برسالة', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final bloc = PurchasesBloc(db: db);
      addTearDown(bloc.close);
      bloc.add(PurchasesSaveOrder());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<PurchasesState>(
            (s) =>
                s.status == PurchasesStatus.ready &&
                s.saved.isEmpty,
          ),
        ),
      );
      expect(bloc.state.saved, isEmpty);
    });
  });
}
