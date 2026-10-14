import 'package:bookstore_pos/core/database/app_database.dart';
import 'package:bookstore_pos/core/database/seed.dart';
import 'package:bookstore_pos/features/inventory/bloc/inventory_bloc.dart';
import 'package:bookstore_pos/features/inventory/view/categories_screen.dart';
import 'package:bookstore_pos/features/inventory/view/products_screen.dart';
import 'package:bookstore_pos/features/settings/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDatabase> _seededDb() async {
  final db = AppDatabase.memory();
  await ensureSeeded(db);
  addTearDown(db.close);
  return db;
}

Widget _wrap(AppDatabase db, Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => InventoryBloc(db: db)..add(InventoryStarted()),
        ),
        BlocProvider(
          create: (_) => SettingsCubit(db: db),
        ),
      ],
      child: child,
    ),
  );
}

/// سطح مكتب واقعي (الافتراضي 800×600 يسبب فيضاً كاذباً)
void _desktopScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('شاشات المخزون', () {
    testWidgets('المنتجات تعرض الأصناف المزروعة + زر منتج جديد',
        (tester) async {
      _desktopScreen(tester);
      final db = await _seededDb();
      await tester.pumpWidget(_wrap(db, const ProductsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('كراسة 100 ورقة'), findsOneWidget);
      expect(find.text('منتج جديد'), findsWidgets);
      expect(find.text('تعديل'), findsWidgets);
    });

    testWidgets('زر منتج جديد يفتح نموذج الإضافة', (tester) async {
      _desktopScreen(tester);
      final db = await _seededDb();
      await tester.pumpWidget(_wrap(db, const ProductsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('منتج جديد').first);
      await tester.pumpAndSettle();

      expect(find.text('منتج جديد', skipOffstage: false), findsWidgets);
      expect(find.text('اسم المنتج *'), findsOneWidget);
      expect(find.text('الباركود * (رئيسي)'), findsOneWidget);
      expect(find.text('إضافة باركود آخر'), findsOneWidget);
      expect(find.text('إضافة المنتج'), findsOneWidget);
    });

    testWidgets('الفئات تعرض الفئات المزروعة + زر فئة جديدة',
        (tester) async {
      _desktopScreen(tester);
      final db = await _seededDb();
      await tester.pumpWidget(_wrap(db, const CategoriesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('قرطاسية'), findsOneWidget);
      expect(find.text('كتب خارجية'), findsOneWidget);
      expect(find.text('فئة جديدة'), findsWidgets);
    });

    testWidgets('فلتر المخزون المنخفض يعمل', (tester) async {
      _desktopScreen(tester);
      final db = await _seededDb();
      await tester.pumpWidget(_wrap(db, const ProductsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('كراسة 100 ورقة'), findsOneWidget);

      await tester.tap(find.text('المخزون المنخفض فقط'));
      await tester.pumpAndSettle();

      // كل البذور فوق الحد — القائمة تصبح فارغة
      expect(find.text('كراسة 100 ورقة'), findsNothing);
      expect(find.text('لا توجد منتجات مطابقة'), findsOneWidget);
    });
  });
}
