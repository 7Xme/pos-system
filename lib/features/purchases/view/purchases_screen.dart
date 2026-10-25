import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/app_database.dart';
import '../../../core/images/product_image_store.dart';
import '../../../core/printing/a4_print_service.dart';
import '../../../core/printing/pdf_purchase.dart';
import '../bloc/purchases_bloc.dart';
import '../../inventory/bloc/inventory_bloc.dart';
import '../../pos/bloc/pos_bloc.dart';
import '../../settings/bloc/settings_cubit.dart';

/// شاشة المشتريات: مسودة قائمة + حفظ أوامر + طباعة PDF + استلام للمخزون
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _supplierCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();
  Timer? _debounce;
  bool _supplierInit = false;

  @override
  void initState() {
    super.initState();
    if (context.read<PurchasesBloc>().state.status ==
        PurchasesStatus.initial) {
      context.read<PurchasesBloc>().add(PurchasesStarted());
    }
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSupplierChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<PurchasesBloc>().add(PurchasesSupplierChanged(
            _supplierCtrl.text,
            _supplierPhoneCtrl.text,
          ));
    });
  }

  void _syncSupplierFields(PurchasesState state) {
    if (_supplierInit) return;
    _supplierInit = true;
    _supplierCtrl.text = state.supplierName;
    _supplierPhoneCtrl.text = state.supplierPhone;
  }

  Future<({List<int>? logoBytes, String currency, String shop, String phone, bool directPrint, String? printerName})>
      _printContext() async {
    final s = context.read<SettingsCubit>().state;
    List<int>? logoBytes;
    try {
      final logoFile = ProductImageStore.fileFor(s.logoPath);
      if (logoFile != null) {
        logoBytes = await logoFile.readAsBytes();
      }
    } catch (_) {
      logoBytes = null;
    }
    return (
      logoBytes: logoBytes,
      currency: s.currency,
      shop: s.shopName,
      phone: s.phone,
      directPrint: s.directPrint,
      printerName: s.printerName,
    );
  }

  Future<void> _printDraft(PurchasesState state) async {
    if (state.draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('القائمة فارغة — أضف أصنافاً أولاً')),
      );
      return;
    }
    final ctx = await _printContext();
    if (!mounted) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    await A4PrintService.printPurchaseOrder(
      shopName: ctx.shop,
      poNumber: 'مسودة-${now.year}${two(now.month)}${two(now.day)}',
      date: now,
      lines: [
        for (final l in state.draft)
          PurchaseLine(
            name: l.name,
            barcode: l.barcode,
            qty: l.qty,
            unitCost: l.unitCost,
          ),
      ],
      currency: ctx.currency,
      phone: ctx.phone.isEmpty ? null : ctx.phone,
      logoBytes: ctx.logoBytes,
      supplierName: state.supplierName,
      supplierPhone:
          state.supplierPhone.isEmpty ? null : state.supplierPhone,
      direct: ctx.directPrint,
      printerName: ctx.printerName,
    );
  }

  Future<void> _printSaved(SavedOrder order) async {
    final bloc = context.read<PurchasesBloc>();
    final items = await bloc.db.itemsOfOrder(order.order.id);
    final lines = <PurchaseLine>[];
    for (final it in items) {
      final prod = await bloc.db.getProduct(it.productId);
      if (prod == null) continue;
      lines.add(PurchaseLine(
        name: prod.name,
        barcode: prod.barcode,
        qty: it.qtyOrdered,
        unitCost: it.unitCost,
      ));
    }
    if (lines.isEmpty || !mounted) return;
    final ctx = await _printContext();
    if (!mounted) return;
    await A4PrintService.printPurchaseOrder(
      shopName: ctx.shop,
      poNumber: order.order.poNumber,
      date: order.order.createdAt,
      lines: lines,
      currency: ctx.currency,
      phone: ctx.phone.isEmpty ? null : ctx.phone,
      logoBytes: ctx.logoBytes,
      supplierName: order.order.supplierName,
      supplierPhone: order.order.supplierPhone,
      direct: ctx.directPrint,
      printerName: ctx.printerName,
    );
  }

  Future<void> _confirm(
    String title,
    String message,
    String okLabel,
    Future<void> Function() action,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    if (yes == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PurchasesBloc, PurchasesState>(
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
          context.read<PurchasesBloc>().add(PurchasesNoticeShown());
          // المخزون تغير (حفظ/استلام/حذف) — حدّث باقي الشاشات
          context.read<InventoryBloc>().add(InventoryStarted());
          context.read<PosBloc>().add(PosCatalogRefreshed());
        }
      },
      builder: (context, state) {
        _syncSupplierFields(state);
        final currency = context.select<SettingsCubit, String>(
          (c) => c.state.currency,
        );
        return Scaffold(
          appBar: AppBar(title: const Text('قوائم المشتريات')),
          body: state.status == PurchasesStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _supplierCard(),
                          const SizedBox(height: 12),
                          _draftCard(state, currency),
                          const SizedBox(height: 12),
                          _savedCard(state, currency),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _supplierCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'المورد (اختياري — يظهر في الورقة المطبوعة)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextField(
                      controller: _supplierCtrl,
                      onChanged: (_) => _onSupplierChanged(),
                      decoration: const InputDecoration(
                        labelText: 'اسم المورد',
                        prefixIcon: Icon(Icons.store_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextField(
                      controller: _supplierPhoneCtrl,
                      onChanged: (_) => _onSupplierChanged(),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'هاتف المورد',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftCard(PurchasesState state, String currency) {
    final bloc = context.read<PurchasesBloc>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'القائمة الحالية (${state.draft.length} صنف) — '
                    'الإجمالي: ${state.draftTotal.toStringAsFixed(2)} $currency',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () =>
                        bloc.add(PurchasesAddLowStock()),
                    icon: const Icon(Icons.warning_amber, size: 24),
                    label: const Text('إضافة المنخفضة تلقائياً'),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _pickProductDialog(),
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text('إضافة منتج'),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: TextButton.icon(
                    onPressed: state.draft.isEmpty
                        ? null
                        : () => bloc.add(PurchasesClearDraft()),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('مسح القائمة'),
                  ),
                ),
              ],
            ),
            if (state.draft.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'القائمة فارغة — أضف الأصناف منخفضة المخزون بضغطة واحدة أو أضف منتجاً يدوياً.',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              const SizedBox(height: 8),
              for (final l in state.draft)
                _DraftLineTile(line: l, currency: currency),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: state.draft.isEmpty
                          ? null
                          : () => bloc.add(PurchasesSaveOrder()),
                      icon: const Icon(Icons.save_outlined, size: 24),
                      label: const Text(
                        'حفظ كأمر شراء',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: state.draft.isEmpty
                          ? null
                          : () => _printDraft(state),
                      icon: const Icon(Icons.print_outlined, size: 24),
                      label: const Text(
                        'طباعة PDF',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedCard(PurchasesState state, String currency) {
    final bloc = context.read<PurchasesBloc>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'أوامر الشراء المحفوظة',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (state.saved.isEmpty)
              const Text(
                'لا توجد أوامر محفوظة بعد.',
                style: TextStyle(color: Colors.grey),
              )
            else
              for (final o in state.saved)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(
                      '${o.order.poNumber} — ${o.order.supplierName}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${o.itemCount} صنف — '
                      '${o.order.totalCost.toStringAsFixed(2)} $currency — '
                      '${o.order.status == 'received' ? 'مُستلم' : 'بانتظار الاستلام'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outlined(
                          onPressed: () => _printSaved(o),
                          icon: const Icon(Icons.print_outlined, size: 22),
                          tooltip: 'طباعة',
                        ),
                        if (o.order.status != 'received') ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: FilledButton.tonal(
                              onPressed: () => _confirm(
                                'تأكيد الاستلام؟',
                                'ستُضاف كميات ${o.order.poNumber} إلى المخزون.',
                                'استلام',
                                () async => bloc.add(
                                  PurchasesReceiveOrder(o.order.id),
                                ),
                              ),
                              child: const Text('استلام'),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () => _confirm(
                            'حذف أمر الشراء؟',
                            'سيُحذف ${o.order.poNumber} نهائياً (دون تغيير المخزون).',
                            'حذف',
                            () async => bloc.add(
                              PurchasesDeleteOrder(o.order.id),
                            ),
                          ),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 22,
                          ),
                          color: Colors.red,
                          tooltip: 'حذف',
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// حوار إضافة منتج للقائمة: بحث مباشر في القاعدة (صفحة واحدة)،
  /// بدل تحميل عشرات الآلاف من المنتجات في الذاكرة عند كل فتح.
  Future<void> _pickProductDialog() async {
    final bloc = context.read<PurchasesBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => _ProductPickerDialog(
        db: bloc.db,
        onPick: (p, qty) => bloc.add(PurchasesAddProduct(
          productId: p.id,
          qty: qty,
          unitCost: p.cost,
        )),
      ),
    );
  }
}

/// منتقي منتجات للمشتريات — استعلام صفحة واحدة مع بحث SQL.
class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.db, required this.onPick});

  final AppDatabase db;
  final void Function(Product product, int qty) onPick;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  static const int _pageSize = 60;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Product> _items = const [];
  bool _loading = true;
  int _qty = 1;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(v));
  }

  Future<void> _search(String query) async {
    final req = ++_request;
    setState(() => _loading = true);
    final page = await widget.db.searchInventoryPage(
      query: query,
      limit: _pageSize,
    );
    if (!mounted || req != _request) return;
    setState(() {
      _items = page.items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة منتج للقائمة'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الباركود...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('لا توجد نتائج'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _items[i];
                            return ListTile(
                              title: Text(p.name),
                              subtitle: Text(
                                'باركود: ${p.barcode} — مخزون: ${p.stockQty}',
                              ),
                              trailing: SizedBox(
                                width: 150,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.outlined(
                                      onPressed: _qty > 1
                                          ? () => setState(() => _qty--)
                                          : null,
                                      icon: const Icon(Icons.remove),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        '$_qty',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton.outlined(
                                      onPressed: () =>
                                          setState(() => _qty++),
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () {
                                widget.onPick(p, _qty);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

/// سطر مسودة: اسم + stepper كمية + سعر وحدة + حذف
class _DraftLineTile extends StatefulWidget {
  final PurchaseLineDraft line;
  final String currency;
  const _DraftLineTile({required this.line, required this.currency});

  @override
  State<_DraftLineTile> createState() => _DraftLineTileState();
}

class _DraftLineTileState extends State<_DraftLineTile> {
  late final TextEditingController _cost;

  @override
  void initState() {
    super.initState();
    _cost = TextEditingController(
      text: widget.line.unitCost.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(_DraftLineTile old) {
    super.didUpdateWidget(old);
    if (old.line.unitCost != widget.line.unitCost) {
      _cost.text = widget.line.unitCost.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PurchasesBloc>();
    final l = widget.line;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'باركود: ${l.barcode} — '
                  'الإجمالي: ${l.total.toStringAsFixed(2)} ${widget.currency}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            height: 48,
            child: TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'سعر الوحدة',
              ),
              onSubmitted: (v) {
                final c = double.tryParse(v.trim());
                if (c != null && c >= 0) {
                  bloc.add(PurchasesUpdateLine(
                    productId: l.productId,
                    qty: l.qty,
                    unitCost: c,
                  ));
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 48,
            child: IconButton.outlined(
              onPressed: () => bloc.add(PurchasesUpdateLine(
                productId: l.productId,
                qty: l.qty + 1,
                unitCost: l.unitCost,
              )),
              icon: const Icon(Icons.add, size: 22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${l.qty}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 48,
            child: IconButton.outlined(
              onPressed: l.qty > 1
                  ? () => bloc.add(PurchasesUpdateLine(
                        productId: l.productId,
                        qty: l.qty - 1,
                        unitCost: l.unitCost,
                      ))
                  : null,
              icon: const Icon(Icons.remove, size: 22),
            ),
          ),
          IconButton(
            onPressed: () => bloc.add(PurchasesRemoveLine(l.productId)),
            icon: const Icon(Icons.delete_outline, size: 24),
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}
