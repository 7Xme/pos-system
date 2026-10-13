import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/app_database.dart';

/// فاتورة محفوظة مع عدد أصنافها (لعرض مختصر في القائمة).
class SavedInvoice extends Equatable {
  final Invoice invoice;
  final int itemCount;

  const SavedInvoice({required this.invoice, required this.itemCount});

  @override
  List<Object?> get props => [invoice, itemCount];
}

/// مولّد رقم مرتجع فريد: طابع زمني بالمللي ثانية + لاحقة عند التعارض.
String nextReturnNumber(DateTime now, [int attempt = 0]) {
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      'RET-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}${now.millisecond.toString().padLeft(3, '0')}';
  return attempt <= 0 ? base : '$base-$attempt';
}

// ── Events ────────────────────────────────────────────────
sealed class SalesEvent extends Equatable {
  const SalesEvent();
  @override
  List<Object?> get props => [];
}

class SalesStarted extends SalesEvent {
  const SalesStarted();
}

/// مرشح التاريخ لقائمة الفواتير: اليوم / يوم محدد / مدة / كل السجل.
class SalesDateFilter extends Equatable {
  final String mode; // today | all | day | range
  final DateTime? day;
  final DateTime? from;
  final DateTime? to;

  const SalesDateFilter._(this.mode, {this.day, this.from, this.to});

  const SalesDateFilter.today() : this._('today');

  const SalesDateFilter.all() : this._('all');

  const SalesDateFilter.day(DateTime d) : this._('day', day: d);

  const SalesDateFilter.range(DateTime f, DateTime t)
      : this._('range', from: f, to: t);

  bool get isToday => mode == 'today';
  bool get isAll => mode == 'all';
  bool get isDay => mode == 'day';
  bool get isRange => mode == 'range';
  bool get isCustom => isDay || isRange;

  static String dayLabel(DateTime d) => '${d.year}/${d.month}/${d.day}';

  /// عنوان بطاقة الإجمالي حسب الفلتر.
  String get totalLabel {
    if (isDay) return 'مبيعات ${dayLabel(day!)}:';
    if (isRange) {
      return 'إجمالي المدة (${dayLabel(from!)} — ${dayLabel(to!)}):';
    }
    if (isAll) return 'إجمالي الكل:';
    return 'مبيعات اليوم:';
  }

  /// نطاق تقرير الإغلاق حسب الفلتر.
  String get closingScope {
    if (isDay) return dayLabel(day!);
    if (isRange) {
      return 'من ${dayLabel(from!)} إلى ${dayLabel(to!)}';
    }
    if (isAll) return 'كل السجل';
    return 'اليوم';
  }

  /// نص الشارة المعروضة عند التخصيص.
  String get chipLabel {
    if (isDay) return dayLabel(day!);
    if (isRange) return '${dayLabel(from!)} — ${dayLabel(to!)}';
    return '';
  }

  @override
  List<Object?> get props => [mode, day, from, to];
}

/// نطاق العرض: اليوم فقط أو كل السجل.
class SalesModeChanged extends SalesEvent {
  final bool todayOnly;
  const SalesModeChanged(this.todayOnly);
  @override
  List<Object?> get props => [todayOnly];
}

/// اختيار يوم محدد لعرض فواتيره.
class SalesDaySelected extends SalesEvent {
  final DateTime day;
  const SalesDaySelected(this.day);
  @override
  List<Object?> get props => [day];
}

/// اختيار مدة معينة (شاملة اليومين).
class SalesRangeSelected extends SalesEvent {
  final DateTime from;
  final DateTime to;
  const SalesRangeSelected(this.from, this.to);
  @override
  List<Object?> get props => [from, to];
}

/// العودة لعرض اليوم (مسح فلتر التاريخ).
class SalesFilterReset extends SalesEvent {
  const SalesFilterReset();
}

class SalesQueryChanged extends SalesEvent {
  final String query;
  const SalesQueryChanged(this.query);
  @override
  List<Object?> get props => [query];
}

/// تحميل سطور فاتورة لمعاينتها (يُعاد استخدامها للطباعة).
class SalesInvoiceOpened extends SalesEvent {
  final int invoiceId;
  const SalesInvoiceOpened(this.invoiceId);
  @override
  List<Object?> get props => [invoiceId];
}

class SalesDetailClosed extends SalesEvent {
  const SalesDetailClosed();
}

class SalesRefreshed extends SalesEvent {
  const SalesRefreshed();
}

/// تحميل ملخص الإغلاق اليومي (Z-report).
class SalesClosingRequested extends SalesEvent {
  const SalesClosingRequested();
}

/// تحميل تقرير الأرباح للنطاق النشط.
class SalesProfitRequested extends SalesEvent {
  const SalesProfitRequested();
}

/// تجهيز الإرجاع: يحسب أقصى كمية قابلة للإرجاع لكل صنف في الفاتورة.
class SalesReturnStarted extends SalesEvent {
  final int invoiceId;
  const SalesReturnStarted(this.invoiceId);
  @override
  List<Object?> get props => [invoiceId];
}

/// تأكيد الإرجاع الجزئي: productId → الكمية المرتجعة.
class SalesReturnConfirmed extends SalesEvent {
  final int invoiceId;
  final Map<int, int> lines;
  final String reason;
  final String? cashier;
  const SalesReturnConfirmed({
    required this.invoiceId,
    required this.lines,
    required this.reason,
    this.cashier,
  });
  @override
  List<Object?> get props => [invoiceId, lines, reason, cashier];
}

class SalesReturnNoticeShown extends SalesEvent {
  const SalesReturnNoticeShown();
}

/// ملخص الإغلاق اليومي للعرض والطباعة.
class ClosingSummary extends Equatable {
  final int invoiceCount;
  final double gross;
  final double discount;
  final double net;
  final double paid;
  final double change;
  final int itemsSold;
  final List<({String name, int qty, double total})> top;

  /// نطاق التقرير (اليوم / تاريخ / من…إلى / كل السجل).
  final String label;

  /// إجمالي المردودات في النطاق + الصافي بعدها.
  final double returnsTotal;

  const ClosingSummary({
    required this.invoiceCount,
    required this.gross,
    required this.discount,
    required this.net,
    required this.paid,
    required this.change,
    required this.itemsSold,
    this.top = const [],
    this.label = 'اليوم',
    this.returnsTotal = 0,
  });

  double get netAfterReturns => net - returnsTotal;

  @override
  List<Object?> get props => [
        invoiceCount,
        gross,
        discount,
        net,
        paid,
        change,
        itemsSold,
        top,
        label,
        returnsTotal,
      ];
}

/// ملخص الربحية للنطاق النشط (بلا تقديرات: الأسطر بلا تكلفة مستبعدة).
class ProfitSummary extends Equatable {
  final double revenue;
  final double refunds;
  final double cogs;
  final double cogsReturned;
  final int noCostLines;
  final List<({String name, int qty, double profit})> top;

  /// نطاق التقرير.
  final String label;

  const ProfitSummary({
    required this.revenue,
    required this.refunds,
    required this.cogs,
    required this.cogsReturned,
    required this.noCostLines,
    this.top = const [],
    this.label = 'اليوم',
  });

  double get netRevenue => revenue - refunds;
  double get netCogs => cogs - cogsReturned;
  double get profit => netRevenue - netCogs;
  double get margin => netRevenue <= 0 ? 0 : profit / netRevenue * 100;

  @override
  List<Object?> get props => [
        revenue,
        refunds,
        cogs,
        cogsReturned,
        noCostLines,
        top,
        label,
      ];
}

// ── State ─────────────────────────────────────────────────
enum SalesStatus { initial, loading, ready }

class SalesState extends Equatable {
  final SalesStatus status;
  final bool todayOnly;
  final String query;
  final List<SavedInvoice> invoices;
  final double dayTotal;
  final Invoice? selected;
  final List<InvoiceItem> selectedItems;
  final bool detailLoading;
  final ClosingSummary? closing;
  final bool closingLoading;
  final SalesDateFilter filter;
  final ProfitSummary? profit;
  final bool profitLoading;

  /// أقصى كمية قابلة للإرجاع لكل صنف (productId → الكمية) — لحوار الإرجاع.
  final Map<int, int> returnCaps;
  final bool returnSaving;
  final String? returnError;
  final String? returnNotice;

  /// آخر مرتجع مسجل (لطباعة الإيصال).
  final ({
    String number,
    String invoiceNumber,
    List<({String name, int qty, double unitPrice, double total})> lines,
    double total,
    String reason,
    String cashier,
  })? lastReturn;

  const SalesState({
    this.status = SalesStatus.initial,
    this.todayOnly = true,
    this.query = '',
    this.invoices = const [],
    this.dayTotal = 0,
    this.selected,
    this.selectedItems = const [],
    this.detailLoading = false,
    this.closing,
    this.closingLoading = false,
    this.filter = const SalesDateFilter.today(),
    this.profit,
    this.profitLoading = false,
    this.returnCaps = const {},
    this.returnSaving = false,
    this.returnError,
    this.returnNotice,
    this.lastReturn,
  });

  int get count => invoices.length;

  SalesState copyWith({
    SalesStatus? status,
    bool? todayOnly,
    String? query,
    List<SavedInvoice>? invoices,
    double? dayTotal,
    Invoice? selected,
    List<InvoiceItem>? selectedItems,
    bool? detailLoading,
    bool clearSelected = false,
    ClosingSummary? closing,
    bool? closingLoading,
    SalesDateFilter? filter,
    ProfitSummary? profit,
    bool? profitLoading,
    Map<int, int>? returnCaps,
    bool? returnSaving,
    String? returnError,
    String? returnNotice,
    ({
      String number,
      String invoiceNumber,
      List<({String name, int qty, double unitPrice, double total})> lines,
      double total,
      String reason,
      String cashier,
    })? lastReturn,
    bool clearLastReturn = false,
  }) {
    return SalesState(
      status: status ?? this.status,
      todayOnly: todayOnly ?? this.todayOnly,
      query: query ?? this.query,
      invoices: invoices ?? this.invoices,
      dayTotal: dayTotal ?? this.dayTotal,
      selected: clearSelected ? null : (selected ?? this.selected),
      selectedItems:
          clearSelected ? const [] : (selectedItems ?? this.selectedItems),
      detailLoading: detailLoading ?? this.detailLoading,
      closing: closing ?? this.closing,
      closingLoading: closingLoading ?? this.closingLoading,
      filter: filter ?? this.filter,
      profit: profit ?? this.profit,
      profitLoading: profitLoading ?? this.profitLoading,
      returnCaps: returnCaps ?? this.returnCaps,
      returnSaving: returnSaving ?? this.returnSaving,
      returnError: returnError,
      returnNotice: returnNotice,
      lastReturn: clearLastReturn ? null : (lastReturn ?? this.lastReturn),
    );
  }

  @override
  List<Object?> get props => [
        status,
        todayOnly,
        query,
        invoices,
        dayTotal,
        selected,
        selectedItems,
        detailLoading,
        closing,
        closingLoading,
        filter,
        profit,
        profitLoading,
        returnCaps,
        returnSaving,
        returnError,
        returnNotice,
        lastReturn,
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class SalesBloc extends Bloc<SalesEvent, SalesState> {
  final AppDatabase db;

  SalesBloc({required this.db}) : super(const SalesState()) {
    on<SalesStarted>(_onStarted);
    on<SalesModeChanged>(_onMode);
    on<SalesDaySelected>(_onDay);
    on<SalesRangeSelected>(_onRange);
    on<SalesFilterReset>(_onReset);
    on<SalesQueryChanged>(_onQuery);
    on<SalesInvoiceOpened>(_onOpen);
    on<SalesDetailClosed>(
      (e, emit) => emit(state.copyWith(clearSelected: true)),
    );
    on<SalesRefreshed>((e, emit) => _onStarted(const SalesStarted(), emit));
    on<SalesClosingRequested>(_onClosing);
    on<SalesProfitRequested>(_onProfit);
    on<SalesReturnStarted>(_onReturnStarted);
    on<SalesReturnConfirmed>(_onReturnConfirmed);
    on<SalesReturnNoticeShown>(
      (e, emit) => emit(state.copyWith(
        returnError: null,
        returnNotice: null,
        returnSaving: false,
      )),
    );
  }

  Future<void> _onStarted(SalesStarted e, Emitter<SalesState> emit) async {
    emit(state.copyWith(status: SalesStatus.loading));
    await _reload(emit);
  }

  Future<void> _onMode(
    SalesModeChanged e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(
      todayOnly: e.todayOnly,
      filter: e.todayOnly
          ? const SalesDateFilter.today()
          : const SalesDateFilter.all(),
    ));
    await _reload(emit);
  }

  Future<void> _onDay(
    SalesDaySelected e,
    Emitter<SalesState> emit,
  ) async {
    final d = DateTime(e.day.year, e.day.month, e.day.day);
    emit(state.copyWith(
      todayOnly: false,
      filter: SalesDateFilter.day(d),
    ));
    await _reload(emit);
  }

  Future<void> _onRange(
    SalesRangeSelected e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(
      todayOnly: false,
      filter: SalesDateFilter.range(e.from, e.to),
    ));
    await _reload(emit);
  }

  Future<void> _onReset(
    SalesFilterReset e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(
      todayOnly: true,
      filter: const SalesDateFilter.today(),
    ));
    await _reload(emit);
  }

  Future<void> _onQuery(
    SalesQueryChanged e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(query: e.query));
    await _reload(emit);
  }

  Future<void> _reload(Emitter<SalesState> emit) async {
    final q = state.query.trim();
    final now = DateTime.now();
    List<Invoice> rows;
    double total;
    if (q.isNotEmpty) {
      // البحث برقم الفاتورة عام دائماً — يتجاهل فلتر التاريخ.
      rows = await db.searchInvoices(q);
      total = await db.salesTotalOnDay(now);
    } else {
      final f = state.filter;
      if (f.isAll) {
        rows = await db.recentInvoices(limit: 200);
        total = await db.salesTotalAll();
      } else if (f.isDay) {
        rows = await db.invoicesOnDay(f.day!);
        total = await db.salesTotalOnDay(f.day!);
      } else if (f.isRange) {
        rows = await db.invoicesInRange(f.from!, f.to!);
        total = await db.salesTotalInRange(f.from!, f.to!);
      } else {
        rows = await db.invoicesOnDay(now);
        total = await db.salesTotalOnDay(now);
      }
    }
    final counts = await db.invoiceItemCounts();
    emit(state.copyWith(
      status: SalesStatus.ready,
      invoices: [
        for (final inv in rows)
          SavedInvoice(invoice: inv, itemCount: counts[inv.id] ?? 0),
      ],
      dayTotal: total,
    ));
  }

  /// حدود النطاق النشط للتقارير (إغلاق/أرباح).
  (DateTime, DateTime) _bounds() {
    final f = state.filter;
    final now = DateTime.now();
    if (f.isDay) return (f.day!, f.day!);
    if (f.isRange) return (f.from!, f.to!);
    if (f.isAll) return (DateTime(2000), now);
    return (now, now);
  }

  Future<void> _onClosing(
    SalesClosingRequested e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(closingLoading: true));
    final f = state.filter;
    // الإغلاق يتبع الفلتر النشط (اليوم افتراضياً).
    final (from, to) = _bounds();
    final s = await db.closingSummaryInRange(from, to);
    final top = await db.topProductsInRange(from, to);
    emit(state.copyWith(
      closingLoading: false,
      closing: ClosingSummary(
        invoiceCount: s.invoiceCount,
        gross: s.gross,
        discount: s.discount,
        net: s.net,
        paid: s.paid,
        change: s.change,
        itemsSold: s.itemsSold,
        top: top,
        label: f.closingScope,
        returnsTotal: s.returns,
      ),
    ));
  }

  Future<void> _onProfit(
    SalesProfitRequested e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(profitLoading: true));
    final f = state.filter;
    final (from, to) = _bounds();
    final p = await db.profitInRange(from, to);
    final top = await db.topProfitProductsInRange(from, to);
    emit(state.copyWith(
      profitLoading: false,
      profit: ProfitSummary(
        revenue: p.revenue,
        refunds: p.refunds,
        cogs: p.cogs,
        cogsReturned: p.cogsReturned,
        noCostLines: p.noCostLines,
        top: top,
        label: f.closingScope,
      ),
    ));
  }

  Future<void> _onReturnStarted(
    SalesReturnStarted e,
    Emitter<SalesState> emit,
  ) async {
    final caps = <int, int>{};
    for (final l in await db.invoiceItemsOf(e.invoiceId)) {
      final already = await db.returnedQty(e.invoiceId, l.productId);
      caps[l.productId] = (l.qty - already).clamp(0, l.qty);
    }
    emit(state.copyWith(
      returnCaps: caps,
      returnSaving: false,
      returnError: null,
      returnNotice: null,
    ));
  }

  Future<void> _onReturnConfirmed(
    SalesReturnConfirmed e,
    Emitter<SalesState> emit,
  ) async {
    final picked = {
      for (final en in e.lines.entries)
        if (en.value > 0) en.key: en.value,
    };
    if (picked.isEmpty) {
      emit(state.copyWith(returnError: 'اختر كمية مرتجعة لصنف واحد على الأقل'));
      return;
    }
    emit(state.copyWith(returnSaving: true, returnError: null));
    try {
      final lines = await db.invoiceItemsOf(e.invoiceId);
      final byId = {for (final l in lines) l.productId: l};
      final now = DateTime.now();
      var attempt = 0;
      var retNo = nextReturnNumber(now);
      while (attempt < 5 && await db.returnNumberExists(retNo)) {
        attempt++;
        retNo = nextReturnNumber(now, attempt);
      }
      final slipLines = [
        for (final en in picked.entries)
          (
            name: byId[en.key]!.productName.isEmpty
                ? 'صنف #${en.key}'
                : byId[en.key]!.productName,
            qty: en.value,
            unitPrice: byId[en.key]!.unitPrice,
            total: byId[en.key]!.unitPrice * en.value,
          ),
      ];
      final slipTotal =
          slipLines.fold<double>(0, (s, l) => s + l.total);
      final invNo = state.invoices
          .where((s) => s.invoice.id == e.invoiceId)
          .firstOrNull
          ?.invoice
          .invoiceNumber;
      await db.createReturn(
        returnNumber: retNo,
        invoiceId: e.invoiceId,
        reason: e.reason,
        cashier: e.cashier,
        items: [
          for (final en in picked.entries)
            ReturnItemsCompanion(
              productId: Value(en.key),
              qty: Value(en.value),
              unitPrice: Value(byId[en.key]!.unitPrice),
              unitCost: Value(byId[en.key]!.unitCost),
              lineTotal: Value(byId[en.key]!.unitPrice * en.value),
              productName: Value(byId[en.key]!.productName),
            ),
        ],
      );
      emit(state.copyWith(
        returnSaving: false,
        returnNotice: 'تم تسجيل المرتجع $retNo واستعادة المخزون',
        returnCaps: const {},
        lastReturn: (
          number: retNo,
          invoiceNumber: invNo ?? '',
          lines: slipLines,
          total: slipTotal,
          reason: e.reason,
          cashier: (e.cashier ?? '').trim().isEmpty
              ? 'كاشير'
              : e.cashier!.trim(),
        ),
      ));
      // حدّث القائمة والإجمالي بعد تغير المخزون
      await _reload(emit);
    } catch (err) {
      emit(state.copyWith(
        returnSaving: false,
        returnError:
            err is StateError ? err.message : 'تعذر تسجيل المرتجع',
      ));
    }
  }

  Future<void> _onOpen(
    SalesInvoiceOpened e,
    Emitter<SalesState> emit,
  ) async {
    final match = state.invoices
        .where((s) => s.invoice.id == e.invoiceId)
        .toList();
    if (match.isEmpty) return;
    emit(state.copyWith(selected: match.first.invoice, detailLoading: true));
    final items = await db.invoiceItemsOf(e.invoiceId);
    emit(state.copyWith(selectedItems: items, detailLoading: false));
  }
}
