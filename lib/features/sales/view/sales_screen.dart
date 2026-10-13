import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/printing/a4_print_service.dart';
import '../../../core/printing/pdf_builders.dart';
import '../../../core/printing/pdf_closing.dart';
import '../../inventory/bloc/inventory_bloc.dart';
import '../../pos/bloc/pos_bloc.dart';
import '../../settings/bloc/settings_cubit.dart';
import '../bloc/sales_bloc.dart';

/// سجل المبيعات: عرض فواتير اليوم/الكل + بحث + معاينة وإعادة طباعة.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (context.read<SalesBloc>().state.status == SalesStatus.initial) {
      context.read<SalesBloc>().add(SalesStarted());
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
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<SalesBloc>().add(SalesQueryChanged(v));
    });
  }

  Future<({List<int>? logoBytes, String currency, String shop, String phone})>
      _printContext() async {
    final s = context.read<SettingsCubit>().state;
    List<int>? logoBytes;
    try {
      final p = s.logoPath;
      if (p != null && File(p).existsSync()) {
        logoBytes = await File(p).readAsBytes();
      }
    } catch (_) {
      logoBytes = null;
    }
    return (
      logoBytes: logoBytes,
      currency: s.currency,
      shop: s.shopName,
      phone: s.phone,
    );
  }

  /// إعادة طباعة فاتورة محفوظة (بالسطور والخصم والدفع كما حُفظت).
  Future<void> _reprint(Invoice inv, List<InvoiceItem> items) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أصناف لهذه الفاتورة')),
      );
      return;
    }
    final ctx = await _printContext();
    if (!mounted) return;
    final settings = context.read<SettingsCubit>().state;
    final paperSize = settings.paperSize;
    await A4PrintService.printInvoice(
      shopName: ctx.shop,
      invoiceNumber: inv.invoiceNumber,
      date: inv.createdAt,
      pageFormat: A4PrintService.paperFormatOf(paperSize),
      direct: settings.directPrint,
      printerName: settings.printerName,
      lines: [
        for (final it in items)
          InvoiceLine(
            name: it.productName.isEmpty
                ? 'صنف #${it.productId}'
                : it.productName,
            qty: it.qty,
            unitPrice: it.unitPrice,
          ),
      ],
      amountPaid: inv.amountPaid,
      discount: inv.discount,
      // القيمة المخزنة مبلغ محسوب بالدرهم؛ العلامة توضح مصدرها فقط.
      discountLabel: inv.discountType == 'percent' ? '%' : null,
      cashier: inv.cashier,
      currency: ctx.currency,
      phone: ctx.phone.isEmpty ? null : ctx.phone,
      logoBytes: ctx.logoBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SalesBloc, SalesState>(
      listenWhen: (a, b) =>
          a.selected?.id != b.selected?.id ||
          (a.detailLoading != b.detailLoading) ||
          a.returnNotice != b.returnNotice ||
          a.returnError != b.returnError,
      listener: (context, state) {
        if (state.selected != null &&
            !state.detailLoading &&
            state.selectedItems.isNotEmpty) {
          final inv = state.selected!;
          final items = state.selectedItems;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showDetailDialog(inv, items);
          });
        }
        if (state.returnNotice != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.returnNotice!)),
          );
        } else if (state.returnError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.returnError!)),
          );
        }
      },
      builder: (context, state) {
        final currency = context.select<SettingsCubit, String>(
          (c) => c.state.currency,
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('سجل المبيعات'),
            actions: [
              IconButton(
                onPressed: _showClosingDialog,
                icon: const Icon(Icons.summarize_outlined),
                tooltip: 'تقرير الإغلاق',
              ),
              IconButton(
                onPressed: _showProfitDialog,
                icon: const Icon(Icons.trending_up_outlined),
                tooltip: 'تقرير الأرباح',
              ),
              IconButton(
                onPressed: () =>
                    context.read<SalesBloc>().add(SalesRefreshed()),
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
              ),
            ],
          ),
          body: state.status == SalesStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _summaryCard(state, currency),
                    Expanded(child: _list(state, currency)),
                  ],
                ),
        );
      },
    );
  }

  /// حوار معاينة الفاتورة الكامل مع إعادة الطباعة.
  Future<void> _showDetailDialog(
    Invoice inv,
    List<InvoiceItem> items,
  ) async {
    final currency = context.read<SettingsCubit>().state.currency;
    final bloc = context.read<SalesBloc>();
    final subtotal = items.fold<double>(0, (s, e) => s + e.lineTotal);
    // حالة الإرجاع تُحسب قبل فتح الحوار (سياق الحوار لا يرى البلوك دائماً).
    final wrap = bloc.state.invoices
        .where((x) => x.invoice.id == inv.id)
        .firstOrNull;
    final locked = wrap?.isFullyReturned ?? false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فاتورة ${inv.invoiceNumber}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('التاريخ: ${_fmtDate(inv.createdAt)}'),
                Text('الكاشير: ${inv.cashier}'),
                if (wrap != null && wrap.hasReturns)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      wrap.isFullyReturned
                          ? 'الحالة: مُرتجعة بالكامل — لا يمكن إرجاعها مجدداً'
                          : 'الحالة: مرتجعة جزئياً (${wrap.returnedQty} من ${wrap.itemCount})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: wrap.isFullyReturned
                            ? Colors.red[800]
                            : Colors.orange[800],
                      ),
                    ),
                  ),
                const Divider(),
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it.productName.isEmpty
                                ? 'صنف #${it.productId}'
                                : it.productName,
                          ),
                        ),
                        Text('${it.qty} × '),
                        Text(it.unitPrice.toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(
                            it.lineTotal.toStringAsFixed(2),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المجموع الفرعي'),
                    Text('${subtotal.toStringAsFixed(2)} $currency'),
                  ],
                ),
                if (inv.discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الخصم'),
                      Text(
                        '-${inv.discount.toStringAsFixed(2)} $currency',
                        style: const TextStyle(color: Color(0xFFC62828)),
                      ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${inv.total.toStringAsFixed(2)} $currency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المدفوع / الباقي'),
                    Text(
                      '${inv.amountPaid.toStringAsFixed(2)} / '
                      '${inv.change.toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          FilledButton.tonalIcon(
            onPressed: locked
                ? null
                : () {
                    Navigator.pop(ctx);
                    _showReturnDialog(inv, items);
                  },
            icon: const Icon(Icons.keyboard_return_outlined),
            label: Text(locked ? 'مُرتجعة بالكامل' : 'إرجاع'),
          ),
          FilledButton.icon(
            onPressed: () => _reprint(inv, items),
            icon: const Icon(Icons.print_outlined),
            label: const Text('إعادة طباعة'),
          ),
        ],
      ),
    );
    bloc.add(SalesDetailClosed());
  }

  /// حوار الإرجاع الجزئي: كمية لكل سطر (بحد الأقصى المتاح) + السبب.
  Future<void> _showReturnDialog(
    Invoice inv,
    List<InvoiceItem> items,
  ) async {
    final bloc = context.read<SalesBloc>();
    final settings = context.read<SettingsCubit>().state;
    bloc.add(SalesReturnStarted(inv.id));
    final picked = {for (final it in items) it.productId: 0};
    final reasonCtrl = TextEditingController();
    try {
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => BlocProvider.value(
          value: bloc,
          child: BlocListener<SalesBloc, SalesState>(
            listenWhen: (a, b) => a.returnNotice != b.returnNotice,
            listener: (c, s) {
              if (s.returnNotice != null) Navigator.pop(c, true);
            },
            child: AlertDialog(
              title: Text('إرجاع من ${inv.invoiceNumber}'),
              content: SizedBox(
                width: 520,
                child: BlocBuilder<SalesBloc, SalesState>(
                  builder: (_, s) {
                    if (s.returnCaps.isEmpty &&
                        !s.returnSaving &&
                        s.returnError == null) {
                      return const SizedBox(
                        height: 140,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return StatefulBuilder(
                      builder: (ctx2, setState) {
                        var pickedTotal = 0.0;
                        for (final it in items) {
                          pickedTotal += (picked[it.productId] ?? 0) *
                              it.unitPrice;
                        }
                        return SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'اختر الكمية المرتجعة لكل صنف (تُستعاد للمخزون).',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => setState(() {
                                    for (final it in items) {
                                      picked[it.productId] =
                                          s.returnCaps[it.productId] ?? 0;
                                    }
                                  }),
                                  icon: const Icon(
                                    Icons.select_all,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'إرجاع الفاتورة كلها',
                                  ),
                                ),
                              ),
                              for (final it in items)
                                _returnLineRow(
                                  it,
                                  s.returnCaps[it.productId] ?? 0,
                                  picked[it.productId] ?? 0,
                                  settings.currency,
                                  (v) => setState(
                                    () => picked[it.productId] = v,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 52,
                                child: TextField(
                                  controller: reasonCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'سبب الإرجاع (اختياري)',
                                    prefixIcon:
                                        Icon(Icons.note_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'إجمالي المرتجع: '
                                '${pickedTotal.toStringAsFixed(2)} '
                                '${settings.currency}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (s.returnError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  s.returnError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: s.returnSaving
                                      ? null
                                      : () => bloc.add(
                                            SalesReturnConfirmed(
                                              invoiceId: inv.id,
                                              lines: Map.of(picked),
                                              reason: reasonCtrl.text,
                                              cashier: settings.cashier,
                                            ),
                                          ),
                                  icon: s.returnSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.check),
                                  label: const Text('تأكيد الإرجاع'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (done == true) {
        final lr = bloc.state.lastReturn;
        bloc.add(const SalesReturnNoticeShown());
        // المخزون تغيّر: حدّث شبكة البيع وشاشة المنتجات فوراً
        if (mounted) {
          context.read<PosBloc>().add(PosCatalogRefreshed());
          context.read<InventoryBloc>().add(InventoryStarted());
        }
        if (lr != null) await _printReturn(lr);
      } else {
        bloc.add(const SalesReturnNoticeShown());
      }
    } finally {
      reasonCtrl.dispose();
    }
  }

  /// سطر إرجاع: الاسم + الكمية المباعة/المتاحة + عدّاد الاختيار.
  Widget _returnLineRow(
    InvoiceItem it,
    int cap,
    int picked,
    String currency,
    ValueChanged<int> onChanged,
  ) {
    final name =
        it.productName.isEmpty ? 'صنف #${it.productId}' : it.productName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'المباع: ${it.qty} — المتاح للإرجاع: $cap',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton.outlined(
              onPressed: picked > 0
                  ? () => onChanged(picked - 1)
                  : null,
              icon: const Icon(Icons.remove, size: 20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$picked',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton.outlined(
              onPressed: picked < cap
                  ? () => onChanged(picked + 1)
                  : null,
              icon: const Icon(Icons.add, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  /// طباعة إيصال المرتجع بمقاس الورق المختار.
  Future<void> _printReturn(
    ({
      String number,
      String invoiceNumber,
      List<({String name, int qty, double unitPrice, double total})> lines,
      double total,
      String reason,
      String cashier,
    }) lr,
  ) async {
    final s = context.read<SettingsCubit>().state;
    try {
      await A4PrintService.printReturn(
        shopName: s.shopName,
        returnNumber: lr.number,
        invoiceNumber: lr.invoiceNumber,
        date: DateTime.now(),
        lines: lr.lines,
        total: lr.total,
        reason: lr.reason,
        cashier: lr.cashier,
        currency: s.currency,
        phone: s.phone.isEmpty ? null : s.phone,
        pageFormat: A4PrintService.paperFormatOf(s.paperSize),
        direct: s.directPrint,
        printerName: s.printerName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الطباعة: $e')),
      );
    }
  }

  /// اختيار فلتر التاريخ: يوم محدد أو مدة معينة أو مسح.
  Future<void> _pickDateFilter() async {
    final bloc = context.read<SalesBloc>();
    final isCustom = bloc.state.filter.isCustom;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فلتر التاريخ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'day'),
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('يوم محدد'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'range'),
                icon: const Icon(Icons.date_range_outlined),
                label: const Text('مدة معينة (من — إلى)'),
              ),
            ),
            if (isCustom) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'clear'),
                  icon: const Icon(Icons.clear),
                  label: const Text('مسح الفلتر (عودة لليوم)'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final today = DateTime.now();
    final first = DateTime(2020);
    if (choice == 'day') {
      final d = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: first,
        lastDate: today,
      );
      if (d != null && mounted) bloc.add(SalesDaySelected(d));
    } else if (choice == 'range') {
      final r = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: today,
      );
      if (r != null && mounted) {
        bloc.add(SalesRangeSelected(r.start, r.end));
      }
    } else if (choice == 'clear' && mounted) {
      bloc.add(const SalesFilterReset());
    }
  }

  /// حوار تقرير إغلاق اليوم (Z-report) مع الطباعة.
  Future<void> _showClosingDialog() async {
    final bloc = context.read<SalesBloc>();
    final settings = context.read<SettingsCubit>().state;
    bloc.add(const SalesClosingRequested());
    await showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: bloc,
        child: AlertDialog(
          title: BlocBuilder<SalesBloc, SalesState>(
            buildWhen: (a, b) => a.closing?.label != b.closing?.label,
            builder: (_, s) =>
                Text('تقرير الإغلاق — ${s.closing?.label ?? 'اليوم'}'),
          ),
          content: SizedBox(
            width: 460,
            child: BlocBuilder<SalesBloc, SalesState>(
              builder: (_, s) {
                if (s.closingLoading || s.closing == null) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _closingRow(
                        'عدد الفواتير:',
                        '${s.closing!.invoiceCount}',
                        settings.currency,
                        bold: true,
                      ),
                      _closingRow(
                        'الأصناف المباعة:',
                        '${s.closing!.itemsSold}',
                        settings.currency,
                      ),
                      const Divider(),
                      _closingRow(
                        'الإجمالي الخام:',
                        s.closing!.gross,
                        settings.currency,
                      ),
                      _closingRow(
                        'الخصومات:',
                        s.closing!.discount,
                        settings.currency,
                        negative: true,
                      ),
                      _closingRow(
                        'الصافي:',
                        s.closing!.net,
                        settings.currency,
                        bold: true,
                      ),
                      if (s.closing!.returnsTotal > 0) ...[
                        _closingRow(
                          'المرتجعات:',
                          s.closing!.returnsTotal,
                          settings.currency,
                          negative: true,
                        ),
                        _closingRow(
                          'الصافي بعد المرتجعات:',
                          s.closing!.netAfterReturns,
                          settings.currency,
                          bold: true,
                        ),
                      ],
                      _closingRow(
                        'المدفوع:',
                        s.closing!.paid,
                        settings.currency,
                      ),
                      _closingRow(
                        'الباقي للزبائن:',
                        s.closing!.change,
                        settings.currency,
                      ),
                      if (s.closing!.top.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'الأعلى مبيعاً:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        for (final t in s.closing!.top)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(child: Text(t.name)),
                                Text(
                                  '${t.qty} — ${t.total.toStringAsFixed(2)} '
                                  '${settings.currency}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => _printClosing(s.closing!),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('طباعة التقرير'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closingRow(
    String label,
    Object value,
    String currency, {
    bool bold = false,
    bool negative = false,
  }) {
    final text = value is double
        ? '${negative ? '-' : ''}${value.toStringAsFixed(2)} $currency'
        : value.toString();
    final style = TextStyle(
      fontSize: bold ? 17 : 15,
      fontWeight: bold ? FontWeight.bold : null,
      color: negative ? const Color(0xFFC62828) : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(text, style: style),
        ],
      ),
    );
  }

  /// طباعة تقرير الإغلاق بمقاس الورق المختار في الإعدادات.
  Future<void> _printClosing(ClosingSummary c) async {
    final s = context.read<SettingsCubit>().state;
    try {
      await A4PrintService.printClosing(
        shopName: s.shopName,
        date: DateTime.now(),
        summary: ClosingSummaryData(
          invoiceCount: c.invoiceCount,
          gross: c.gross,
          discount: c.discount,
          net: c.net,
          paid: c.paid,
          change: c.change,
          itemsSold: c.itemsSold,
          top: c.top,
          scopeLabel: c.label,
          returnsTotal: c.returnsTotal,
        ),
        currency: s.currency,
        phone: s.phone.isEmpty ? null : s.phone,
        pageFormat: A4PrintService.paperFormatOf(s.paperSize),
        direct: s.directPrint,
        printerName: s.printerName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الطباعة: $e')),
      );
    }
  }

  /// حوار تقرير الأرباح للنطاق النشط (بلا تقديرات).
  Future<void> _showProfitDialog() async {
    final bloc = context.read<SalesBloc>();
    final settings = context.read<SettingsCubit>().state;
    bloc.add(const SalesProfitRequested());
    await showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: bloc,
        child: AlertDialog(
          title: BlocBuilder<SalesBloc, SalesState>(
            buildWhen: (a, b) => a.profit?.label != b.profit?.label,
            builder: (_, s) =>
                Text('تقرير الأرباح — ${s.profit?.label ?? 'اليوم'}'),
          ),
          content: SizedBox(
            width: 460,
            child: BlocBuilder<SalesBloc, SalesState>(
              builder: (_, s) {
                if (s.profitLoading || s.profit == null) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final p = s.profit!;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _closingRow(
                        'إيراد المبيعات:',
                        p.revenue,
                        settings.currency,
                      ),
                      _closingRow(
                        'المردودات:',
                        p.refunds,
                        settings.currency,
                        negative: true,
                      ),
                      _closingRow(
                        'صافي الإيراد:',
                        p.netRevenue,
                        settings.currency,
                        bold: true,
                      ),
                      _closingRow(
                        'تكلفة المباع:',
                        p.netCogs,
                        settings.currency,
                        negative: true,
                      ),
                      _closingRow(
                        'الربح الإجمالي:',
                        p.profit,
                        settings.currency,
                        bold: true,
                      ),
                      _closingRow(
                        'الهامش:',
                        '${p.margin.toStringAsFixed(1)}%',
                        settings.currency,
                      ),
                      if (p.noCostLines > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'ملاحظة: ${p.noCostLines} سطر بلا تكلفة مسجلة '
                          '(فواتير قبل التحديث) — مستبعدة من التكلفة.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (p.top.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'الأعلى ربحاً:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        for (final t in p.top)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(child: Text(t.name)),
                                Text(
                                  '${t.profit.toStringAsFixed(2)} '
                                  '${settings.currency}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => _printProfit(p),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('طباعة التقرير'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// طباعة تقرير الأرباح بمقاس الورق المختار في الإعدادات.
  Future<void> _printProfit(ProfitSummary p) async {
    final s = context.read<SettingsCubit>().state;
    try {
      await A4PrintService.printProfit(
        shopName: s.shopName,
        scopeLabel: p.label,
        revenue: p.revenue,
        refunds: p.refunds,
        cogs: p.cogs,
        cogsReturned: p.cogsReturned,
        noCostLines: p.noCostLines,
        top: p.top,
        currency: s.currency,
        phone: s.phone.isEmpty ? null : s.phone,
        pageFormat: A4PrintService.paperFormatOf(s.paperSize),
        direct: s.directPrint,
        printerName: s.printerName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الطباعة: $e')),
      );
    }
  }

  Widget _summaryCard(SalesState state, String currency) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${state.filter.totalLabel} '
                    '${state.dayTotal.toStringAsFixed(2)} $currency',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: _pickDateFilter,
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: 'اختيار تاريخ محدد أو مدة',
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('اليوم')),
                    ButtonSegment(value: false, label: Text('الكل')),
                  ],
                  selected: state.filter.isCustom
                      ? const <bool>{}
                      : {state.todayOnly},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => context
                      .read<SalesBloc>()
                      .add(SalesModeChanged(s.first)),
                ),
              ],
            ),
            if (state.filter.isCustom) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: InputChip(
                  label: Text(state.filter.chipLabel),
                  avatar: const Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                  ),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => context
                      .read<SalesBloc>()
                      .add(const SalesFilterReset()),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'ابحث برقم الفاتورة...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(SalesState state, String currency) {
    if (state.invoices.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد فواتير.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: state.invoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final s = state.invoices[i];
        final inv = s.invoice;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined, size: 30),
            title: Text(
              inv.invoiceNumber,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${_fmtDate(inv.createdAt)} — ${s.itemCount} صنف'
              '${inv.discount > 0 ? ' — خصم ${inv.discount.toStringAsFixed(2)}' : ''}'
              ' — ${inv.cashier}'
              '${s.isFullyReturned ? ' — مُرتجعة بالكامل' : s.hasReturns ? ' — مرتجعة جزئياً' : ''}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.hasReturns)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(
                        s.isFullyReturned ? 'مُرتجعة' : 'مرتجعة جزئياً',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: s.isFullyReturned
                          ? Colors.red[50]
                          : Colors.orange[50],
                      side: BorderSide(
                        color: s.isFullyReturned
                            ? Colors.red
                            : Colors.orange,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Text(
                  '${inv.total.toStringAsFixed(2)} $currency',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'عرض',
                  onPressed: () => context
                      .read<SalesBloc>()
                      .add(SalesInvoiceOpened(inv.id)),
                  icon: const Icon(Icons.visibility_outlined, size: 22),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: s.isFullyReturned
                      ? 'مُرتجعة بالكامل — لا يمكن إرجاعها'
                      : 'إرجاع',
                  onPressed: s.isFullyReturned
                      ? null
                      : () async {
                          final items = await context
                              .read<SalesBloc>()
                              .db
                              .invoiceItemsOf(inv.id);
                          if (!mounted) return;
                          await _showReturnDialog(inv, items);
                        },
                  icon: const Icon(
                    Icons.keyboard_return_outlined,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'إعادة طباعة',
                  onPressed: () async {
                    final items = await context
                        .read<SalesBloc>()
                        .db
                        .invoiceItemsOf(inv.id);
                    if (!mounted) return;
                    await _reprint(inv, items);
                  },
                  icon: const Icon(Icons.print_outlined, size: 22),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmtDate(DateTime d) {
    return DateFormat('yyyy/MM/dd HH:mm').format(d);
  }
}
