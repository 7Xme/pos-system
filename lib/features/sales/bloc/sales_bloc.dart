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

// ── Events ────────────────────────────────────────────────
sealed class SalesEvent extends Equatable {
  const SalesEvent();
  @override
  List<Object?> get props => [];
}

class SalesStarted extends SalesEvent {
  const SalesStarted();
}

/// نطاق العرض: اليوم فقط أو كل السجل.
class SalesModeChanged extends SalesEvent {
  final bool todayOnly;
  const SalesModeChanged(this.todayOnly);
  @override
  List<Object?> get props => [todayOnly];
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

  const SalesState({
    this.status = SalesStatus.initial,
    this.todayOnly = true,
    this.query = '',
    this.invoices = const [],
    this.dayTotal = 0,
    this.selected,
    this.selectedItems = const [],
    this.detailLoading = false,
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
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class SalesBloc extends Bloc<SalesEvent, SalesState> {
  final AppDatabase db;

  SalesBloc({required this.db}) : super(const SalesState()) {
    on<SalesStarted>(_onStarted);
    on<SalesModeChanged>(_onMode);
    on<SalesQueryChanged>(_onQuery);
    on<SalesInvoiceOpened>(_onOpen);
    on<SalesDetailClosed>(
      (e, emit) => emit(state.copyWith(clearSelected: true)),
    );
    on<SalesRefreshed>((e, emit) => _onStarted(const SalesStarted(), emit));
  }

  Future<void> _onStarted(SalesStarted e, Emitter<SalesState> emit) async {
    emit(state.copyWith(status: SalesStatus.loading));
    await _reload(emit);
  }

  Future<void> _onMode(
    SalesModeChanged e,
    Emitter<SalesState> emit,
  ) async {
    emit(state.copyWith(todayOnly: e.todayOnly));
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
    List<Invoice> rows;
    if (q.isNotEmpty) {
      rows = await db.searchInvoices(q);
    } else if (state.todayOnly) {
      rows = await db.invoicesOnDay(DateTime.now());
    } else {
      rows = await db.recentInvoices(limit: 200);
    }
    final counts = await db.invoiceItemCounts();
    final dayTotal = await db.salesTotalOnDay(DateTime.now());
    emit(state.copyWith(
      status: SalesStatus.ready,
      invoices: [
        for (final inv in rows)
          SavedInvoice(invoice: inv, itemCount: counts[inv.id] ?? 0),
      ],
      dayTotal: dayTotal,
    ));
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
