import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/printing/a4_print_service.dart';
import '../../../core/printing/pdf_builders.dart';
import '../../../core/printing/pdf_closing.dart';
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
    final paperSize = context.read<SettingsCubit>().state.paperSize;
    await A4PrintService.printInvoice(
      shopName: ctx.shop,
      invoiceNumber: inv.invoiceNumber,
      date: inv.createdAt,
      pageFormat: A4PrintService.paperFormatOf(paperSize),
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
          (a.detailLoading != b.detailLoading),
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
                tooltip: 'تقرير إغلاق اليوم',
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
          title: const Text('تقرير إغلاق اليوم'),
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
        ),
        currency: s.currency,
        phone: s.phone.isEmpty ? null : s.phone,
        pageFormat: A4PrintService.paperFormatOf(s.paperSize),
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
                    'مبيعات اليوم: ${state.dayTotal.toStringAsFixed(2)} $currency',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('اليوم')),
                    ButtonSegment(value: false, label: Text('الكل')),
                  ],
                  selected: {state.todayOnly},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => context
                      .read<SalesBloc>()
                      .add(SalesModeChanged(s.first)),
                ),
              ],
            ),
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
              ' — ${inv.cashier}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
