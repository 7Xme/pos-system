import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/inventory_bloc.dart';

/// شاشة الفئات: إضافة/تعديل/حذف مع عدد المنتجات
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<void> _editDialog(
    BuildContext context,
    InventoryCategory? category,
  ) async {
    final bloc = context.read<InventoryBloc>();
    final ctrl = TextEditingController(text: category?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? 'فئة جديدة' : 'تعديل الفئة'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الفئة *',
            ),
            onSubmitted: (_) =>
                Navigator.pop(ctx, ctrl.text.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty && context.mounted) {
      bloc.add(InventoryCategorySaved(id: category?.id, name: name));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InventoryCategory category,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفئة'),
        content: Text(
          category.productCount > 0
              ? '«${category.name}» تحتوي على ${category.productCount} منتج — سيصبحون بدون فئة. حذف؟'
              : 'حذف فئة «${category.name}»؟',
        ),
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
      context.read<InventoryBloc>().add(
            InventoryCategoryDeleted(category.id),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('الفئات'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => _editDialog(context, null),
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text('فئة جديدة'),
                  ),
                ),
              ),
            ],
          ),
          body: state.status == InventoryStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : state.categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.category_outlined,
                            size: 56,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'لا توجد فئات — أضف أول فئة',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _editDialog(context, null),
                            icon: const Icon(Icons.add),
                            label: const Text('فئة جديدة'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.categories.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final c = state.categories[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: const Icon(
                              Icons.folder_outlined,
                              size: 32,
                            ),
                            title: Text(
                              c.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${c.productCount} منتج',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 48,
                                  width: 48,
                                  child: IconButton.outlined(
                                    onPressed: () =>
                                        _editDialog(context, c),
                                    icon:
                                        const Icon(Icons.edit, size: 22),
                                    tooltip: 'تعديل',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 48,
                                  width: 48,
                                  child: IconButton.outlined(
                                    onPressed: () =>
                                        _confirmDelete(context, c),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 22,
                                    ),
                                    color: Colors.red,
                                    tooltip: 'حذف',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
