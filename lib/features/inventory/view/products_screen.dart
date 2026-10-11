import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/bloc/settings_cubit.dart';
import '../bloc/inventory_bloc.dart';
import 'product_form_dialog.dart';

/// شاشة المنتجات: بحث + فلترة + إضافة/تعديل/حذف + تنبيه المخزون
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (context.read<InventoryBloc>().state.status ==
        InventoryStatus.initial) {
      context.read<InventoryBloc>().add(InventoryStarted());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        context.read<InventoryBloc>().add(InventoryQueryChanged(v));
      }
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InventoryProduct p,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text('حذف «${p.name}» نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      context.read<InventoryBloc>().add(InventoryProductDeleted(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryBloc, InventoryState>(
      listenWhen: (a, b) => a.notice != b.notice || a.error != b.error,
      listener: (context, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!)),
          );
        } else if (state.notice != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.notice!)),
          );
          context.read<InventoryBloc>().add(InventoryNoticeShown());
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('المنتجات والمخزون'),
            actions: [
              if (state.lowStockCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Chip(
                    avatar: const Icon(
                      Icons.warning_amber,
                      color: Colors.red,
                    ),
                    label: Text(
                      'مخزون منخفض: ${state.lowStockCount}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // شريط الأدوات — لمس كبير
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      height: 56,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearch,
                        style: const TextStyle(fontSize: 17),
                        decoration: const InputDecoration(
                          hintText: 'ابحث بالاسم أو الباركود...',
                          prefixIcon: Icon(Icons.search, size: 26),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      height: 56,
                      child: DropdownButtonFormField<int?>(
                        initialValue: state.categoryFilterId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('كل الفئات'),
                          ),
                          for (final c in state.categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: (v) => context
                            .read<InventoryBloc>()
                            .add(InventoryCategorySelected(v)),
                      ),
                    ),
                    FilterChip(
                      label: const Text(
                        'المخزون المنخفض فقط',
                        style: TextStyle(fontSize: 16),
                      ),
                      selected: state.lowStockOnly,
                      onSelected: (v) => context
                          .read<InventoryBloc>()
                          .add(InventoryLowStockToggled(v)),
                      showCheckmark: true,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: () => showProductFormDialog(context, null),
                        icon: const Icon(Icons.add, size: 26),
                        label: const Text(
                          'منتج جديد',
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: state.status == InventoryStatus.loading
                      ? const Center(child: CircularProgressIndicator())
                      : state.products.isEmpty
                          ? _emptyState(context, state)
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                childAspectRatio: 0.92,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: state.products.length,
                              itemBuilder: (ctx, i) => _ProductTile(
                                product: state.products[i],
                                onEdit: () => showProductFormDialog(
                                  context,
                                  state.products[i],
                                ),
                                onDelete: () => _confirmDelete(
                                  context,
                                  state.products[i],
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, InventoryState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 56),
          const SizedBox(height: 12),
          Text(
            state.query.isNotEmpty || state.lowStockOnly
                ? 'لا توجد منتجات مطابقة'
                : 'لا توجد منتجات بعد — أضف أول منتج',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => showProductFormDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('منتج جديد'),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final InventoryProduct product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final low = product.isLowStock;
    final currency = context.select<SettingsCubit, String>(
      (c) => c.state.currency,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // صورة مصغرة
            SizedBox(
              height: 72,
              width: 72,
              child: _thumb(product.imagePath),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'باركود: ${product.barcode}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${product.price.toStringAsFixed(2)} $currency',
              style: const TextStyle(fontSize: 15),
            ),
            Text(
              low
                  ? 'منخفض: ${product.stockQty} (الأدنى ${product.minStock})'
                  : 'متاح: ${product.stockQty}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: low ? Colors.red : Colors.green[800],
              ),
            ),
            if (product.categoryName != null)
              Text(
                product.categoryName!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  height: 44,
                  width: 44,
                  child: IconButton.outlined(
                    onPressed: () =>
                        context.read<InventoryBloc>().add(
                              InventoryFavoriteToggled(
                                product.id,
                                !product.isFavorite,
                              ),
                            ),
                    icon: Icon(
                      product.isFavorite
                          ? Icons.star
                          : Icons.star_outline,
                      size: 22,
                    ),
                    color: product.isFavorite
                        ? Colors.amber[800]
                        : Colors.grey,
                    tooltip: 'تثبيت كزر اختصار',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 20),
                      label: const Text('تعديل'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  width: 48,
                  child: IconButton.outlined(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 22),
                    color: Colors.red,
                    tooltip: 'حذف',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String? path) {
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(path), fit: BoxFit.cover),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.image_outlined, size: 36, color: Colors.grey),
    );
  }
}
