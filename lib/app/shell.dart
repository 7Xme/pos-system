import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/barcode/barcode_scanner_service.dart';
import '../features/backup/view/backup_screen.dart';
import '../features/inventory/bloc/inventory_bloc.dart';
import '../features/pos/bloc/pos_bloc.dart';
import '../features/purchases/view/purchases_screen.dart';
import '../features/sales/bloc/sales_bloc.dart';
import '../features/sales/view/sales_screen.dart';
import '../features/settings/view/settings_screen.dart';
import '../features/inventory/view/categories_screen.dart';
import '../features/inventory/view/products_screen.dart';
import '../features/pos/view/pos_screen.dart';

/// الهيكل الرئيسي: تنقل جانبي (يمين في RTL) بين البيع والمخزون والفئات
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    BarcodeScannerService.captureEnabled = _index == 0;
    final inv = context.read<InventoryBloc>();
    if (inv.state.status == InventoryStatus.initial) {
      inv.add(InventoryStarted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = context.select<InventoryBloc, int>(
      (b) => b.state.lowStockCount,
    );
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() => _index = i);
              // الماسح يعمل فقط في شاشة البيع حتى لا يلتهم كتابة الشاشات الأخرى
              BarcodeScannerService.captureEnabled = i == 0;
              if (BarcodeScannerService.captureEnabled) {
                BarcodeScannerService.reset();
              }
              // تحديث الشبكة والاختصارات عند العودة للبيع
              // (قد يتغير المخزون من إرجاع أو استلام)
              if (i == 0) {
                context.read<PosBloc>().add(PosCatalogRefreshed());
              }
              // تحديث سجل المبيعات عند فتحه (قد تُحفظ فواتير جديدة)
              if (i == 4) {
                context.read<SalesBloc>().add(SalesRefreshed());
              }
            },
            labelType: NavigationRailLabelType.all,
            minWidth: 96,
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.point_of_sale, size: 30),
                selectedIcon: Icon(Icons.point_of_sale, size: 30),
                label: Text(
                  'نقطة البيع',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: lowCount > 0,
                  label: Text('$lowCount'),
                  child: const Icon(Icons.inventory_2_outlined, size: 30),
                ),
                selectedIcon: Badge(
                  isLabelVisible: lowCount > 0,
                  label: Text('$lowCount'),
                  child: const Icon(Icons.inventory_2, size: 30),
                ),
                label: const Text(
                  'المنتجات',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.category_outlined, size: 30),
                selectedIcon: Icon(Icons.category, size: 30),
                label: Text(
                  'الفئات',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.shopping_cart_outlined, size: 30),
                selectedIcon: Icon(Icons.shopping_cart, size: 30),
                label: Text(
                  'المشتريات',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined, size: 30),
                selectedIcon: Icon(Icons.receipt_long, size: 30),
                label: Text(
                  'المبيعات',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.backup_outlined, size: 30),
                selectedIcon: Icon(Icons.backup, size: 30),
                label: Text(
                  'نسخ احتياطي',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings_outlined, size: 30),
                selectedIcon: Icon(Icons.settings, size: 30),
                label: Text(
                  'الإعدادات',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                PosScreen(),
                ProductsScreen(),
                CategoriesScreen(),
                PurchasesScreen(),
                SalesScreen(),
                BackupScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
