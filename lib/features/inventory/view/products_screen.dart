import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/images/product_image_store.dart';
import '../../../core/printing/a4_print_service.dart';
import '../../../core/widgets/product_hover_preview.dart';
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
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    if (context.read<InventoryBloc>().state.status ==
        InventoryStatus.initial) {
      context.read<InventoryBloc>().add(InventoryStarted());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// تحميل الصفحة التالية قبل الوصول لنهاية الشبكة بهامش بسيط.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.extentAfter > 600) return;
    final bloc = context.read<InventoryBloc>();
    if (bloc.state.hasMore && !bloc.state.loadingMore) {
      bloc.add(InventoryLoadMore());
    }
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
            title: Text(
              state.totalCount > 0
                  ? 'المنتجات والمخزون (${state.totalCount})'
                  : 'المنتجات والمخزون',
            ),
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
                              controller: _scrollCtrl,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                childAspectRatio: 0.92,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: state.products.length +
                                  (state.hasMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i >= state.products.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final p = state.products[i];
                                return _ProductTile(
                                  product: p,
                                  onEdit: () =>
                                      showProductFormDialog(context, p),
                                  onDelete: () => _confirmDelete(context, p),
                                );
                              },
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
              child: ProductHoverPreview(
                imagePath: product.imagePath,
                child: _thumb(context, product.imagePath),
              ),
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
              'باركود: ${product.barcode}'
              '${product.extraBarcodesCount > 0 ? '  (+${product.extraBarcodesCount} إضافي)' : ''}',
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
                const SizedBox(width: 6),
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
                const SizedBox(width: 6),
                SizedBox(
                  height: 44,
                  width: 44,
                  child: IconButton.outlined(
                    onPressed: () =>
                        _printLabels(context, product, currency),
                    icon: const Icon(
                      Icons.barcode_reader,
                      size: 22,
                    ),
                    tooltip: 'طباعة ملصقات باركود',
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 44,
                  width: 44,
child: IconButton.outlined(
                      onPressed: product.hasHistory ? null : onDelete,
                      icon: const Icon(Icons.delete_outline, size: 22),
                      color: Colors.red,
                      tooltip: product.hasHistory
                          ? 'له سجل مبيعات/مشتريات — يمكن تعطيله بدل حذفه'
                          : 'حذف',
                    ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _thumb(BuildContext context, String? path) {
    final file = ProductImageStore.fileFor(path);
    if (file != null) {
      // فكّ الصورة بحجم العرض فقط (72px) بدل الدقة الكاملة — أسرع وأخف.
      final cacheWidth =
          (72 * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => _thumbPlaceholder(),
        ),
      );
    }
    return _thumbPlaceholder();
  }

  Widget _thumbPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.image_outlined, size: 36, color: Colors.grey),
    );
  }

  /// حوار عدد النسخ ثم طباعة ملصقات باركود الصنف.
  Future<void> _printLabels(
    BuildContext context,
    InventoryProduct product,
    String currency,
  ) async {
    final ctrl = TextEditingController(text: '12');
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملصقات: ${product.name}'),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد الملصقات (1-200)',
            ),
            onSubmitted: (_) => Navigator.pop(
              ctx,
              int.tryParse(ctrl.text.trim()),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              int.tryParse(ctrl.text.trim()),
            ),
            child: const Text('طباعة'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (count == null || !context.mounted) return;
    final n = count.clamp(1, 200);
    final settings = context.read<SettingsCubit>().state;
    try {
      await A4PrintService.printBarcodeSheet(
        List.filled(
          n,
          (
            name: product.name,
            barcode: product.barcode,
            price: product.price,
          ),
        ),
        currency: currency,
        direct: settings.directPrint,
        printerName: settings.printerName,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الطباعة: $e')),
      );
    }
  }
}
