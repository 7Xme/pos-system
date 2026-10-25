import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/drift_repositories.dart';
import 'package:bookstore_pos/features/import/view/import_screen.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/pos/bloc/pos_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبار واجهة استيراد الكتالوج: العرض الابتدائي فقط (بدون فتح نافذة
/// اختيار المجلد الأصلية).
void main() {
  testWidgets('شاشة الاستيراد: زر الاستيراد معطّل قبل اختيار مجلد',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // إنشاء المخطط

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => InventoryBloc(db: db)),
            BlocProvider(
              create: (_) => PosBloc(
                repo: DriftCatalogRepository(db),
                checkoutRepo: DriftCheckoutRepository(db),
              ),
            ),
          ],
          child: const ImportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('استيراد المنتجات'), findsOneWidget);
    expect(find.text('مصدر البيانات'), findsOneWidget);
    expect(find.textContaining('المنتجات الحالية في التطبيق'), findsOneWidget);
    expect(find.text('اختيار مجلد البيانات'), findsOneWidget);
    expect(find.text('نسخ الصور إلى مجلد التطبيق'), findsOneWidget);

    final importButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'استيراد الآن'),
    );
    expect(importButton.onPressed, isNull);
  });
}
