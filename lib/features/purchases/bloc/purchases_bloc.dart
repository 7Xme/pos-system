import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/app_database.dart';

/// سطر في مسودة قائمة المشتريات
class PurchaseLineDraft extends Equatable {
  final int productId;
  final String name;
  final String barcode;
  final int qty;
  final double unitCost;

  const PurchaseLineDraft({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.qty,
    required this.unitCost,
  });

  double get total => qty * unitCost;

  PurchaseLineDraft copyWith({int? qty, double? unitCost}) {
    return PurchaseLineDraft(
      productId: productId,
      name: name,
      barcode: barcode,
      qty: qty ?? this.qty,
      unitCost: unitCost ?? this.unitCost,
    );
  }

  @override
  List<Object?> get props => [productId, name, barcode, qty, unitCost];
}

/// أمر شراء محفوظ مع عدد سطوره
class SavedOrder extends Equatable {
  final PurchaseOrder order;
  final int itemCount;

  const SavedOrder({required this.order, required this.itemCount});

  @override
  List<Object?> get props => [order, itemCount];
}

/// مولّد رقم أمر شراء فريد: طابع زمني بالمللي ثانية + لاحقة عند التعارض.
String nextPoNumber(DateTime now, [int attempt = 0]) {
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      'PO-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}${now.millisecond.toString().padLeft(3, '0')}';
  return attempt <= 0 ? base : '$base-$attempt';
}

// ── Events ────────────────────────────────────────────────
sealed class PurchasesEvent extends Equatable {
  const PurchasesEvent();
  @override
  List<Object?> get props => [];
}

class PurchasesStarted extends PurchasesEvent {}

/// إضافة كل المنتجات منخفضة المخزون للمسودة
class PurchasesAddLowStock extends PurchasesEvent {}

class PurchasesAddProduct extends PurchasesEvent {
  final int productId;
  final int qty;
  final double unitCost;
  const PurchasesAddProduct({
    required this.productId,
    required this.qty,
    required this.unitCost,
  });
  @override
  List<Object?> get props => [productId, qty, unitCost];
}

class PurchasesUpdateLine extends PurchasesEvent {
  final int productId;
  final int qty;
  final double unitCost;
  const PurchasesUpdateLine({
    required this.productId,
    required this.qty,
    required this.unitCost,
  });
  @override
  List<Object?> get props => [productId, qty, unitCost];
}

class PurchasesRemoveLine extends PurchasesEvent {
  final int productId;
  const PurchasesRemoveLine(this.productId);
  @override
  List<Object?> get props => [productId];
}

class PurchasesClearDraft extends PurchasesEvent {}

class PurchasesSupplierChanged extends PurchasesEvent {
  final String name;
  final String phone;
  const PurchasesSupplierChanged(this.name, this.phone);
  @override
  List<Object?> get props => [name, phone];
}

class PurchasesSaveOrder extends PurchasesEvent {}

class PurchasesReceiveOrder extends PurchasesEvent {
  final int id;
  const PurchasesReceiveOrder(this.id);
  @override
  List<Object?> get props => [id];
}

class PurchasesDeleteOrder extends PurchasesEvent {
  final int id;
  const PurchasesDeleteOrder(this.id);
  @override
  List<Object?> get props => [id];
}

class PurchasesNoticeShown extends PurchasesEvent {}

// ── State ─────────────────────────────────────────────────
enum PurchasesStatus { initial, loading, ready, saving, failure }

class PurchasesState extends Equatable {
  final PurchasesStatus status;
  final List<PurchaseLineDraft> draft;
  final String supplierName;
  final String supplierPhone;
  final List<SavedOrder> saved;
  final String? error;
  final String? notice;

  const PurchasesState({
    this.status = PurchasesStatus.initial,
    this.draft = const [],
    this.supplierName = '',
    this.supplierPhone = '',
    this.saved = const [],
    this.error,
    this.notice,
  });

  double get draftTotal =>
      draft.fold<double>(0, (s, e) => s + e.total);

  PurchasesState copyWith({
    PurchasesStatus? status,
    List<PurchaseLineDraft>? draft,
    String? supplierName,
    String? supplierPhone,
    List<SavedOrder>? saved,
    String? error,
    String? notice,
  }) {
    return PurchasesState(
      status: status ?? this.status,
      draft: draft ?? this.draft,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      saved: saved ?? this.saved,
      error: error,
      notice: notice,
    );
  }

  @override
  List<Object?> get props => [
        status,
        draft,
        supplierName,
        supplierPhone,
        saved,
        error,
        notice,
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class PurchasesBloc extends Bloc<PurchasesEvent, PurchasesState> {
  final AppDatabase db;

  PurchasesBloc({required this.db}) : super(const PurchasesState()) {
    on<PurchasesStarted>(_onStarted);
    on<PurchasesAddLowStock>(_onAddLowStock);
    on<PurchasesAddProduct>(_onAddProduct);
    on<PurchasesUpdateLine>(_onUpdateLine);
    on<PurchasesRemoveLine>(_onRemoveLine);
    on<PurchasesClearDraft>(
      (e, emit) => emit(state.copyWith(draft: [])),
    );
    on<PurchasesSupplierChanged>(
      (e, emit) => emit(state.copyWith(
        supplierName: e.name,
        supplierPhone: e.phone,
      )),
    );
    on<PurchasesSaveOrder>(_onSaveOrder);
    on<PurchasesReceiveOrder>(_onReceive);
    on<PurchasesDeleteOrder>(_onDelete);
    on<PurchasesNoticeShown>(
      (e, emit) => emit(state.copyWith(status: PurchasesStatus.ready)),
    );
  }

  Future<void> _onStarted(
    PurchasesStarted e,
    Emitter<PurchasesState> emit,
  ) async {
    emit(state.copyWith(status: PurchasesStatus.loading));
    emit(state.copyWith(
      status: PurchasesStatus.ready,
      saved: await _loadSaved(),
    ));
  }

  Future<List<SavedOrder>> _loadSaved() async {
    final orders = await db.allPurchaseOrders();
    final counts = await db.purchaseItemCounts();
    return orders
        .map((o) => SavedOrder(
              order: o,
              itemCount: counts[o.id] ?? 0,
            ))
        .toList();
  }

  Future<void> _onAddLowStock(
    PurchasesAddLowStock e,
    Emitter<PurchasesState> emit,
  ) async {
    final low = await db.lowStockProducts();
    final existing = state.draft.map((l) => l.productId).toSet();
    var added = 0;
    final draft = List<PurchaseLineDraft>.from(state.draft);
    for (final p in low) {
      if (existing.contains(p.id)) continue;
      // نقترح التعبئة حتى ضعف الحد الأدنى
      final qty = (p.minStock * 2 - p.stockQty).clamp(1, 1 << 30);
      draft.add(PurchaseLineDraft(
        productId: p.id,
        name: p.name,
        barcode: p.barcode,
        qty: qty,
        unitCost: p.cost,
      ));
      added++;
    }
    if (added == 0) {
      emit(state.copyWith(
        status: PurchasesStatus.failure,
        error: 'لا توجد أصناف منخفضة جديدة للإضافة',
      ));
      emit(state.copyWith(status: PurchasesStatus.ready, error: null));
      return;
    }
    emit(state.copyWith(
      draft: draft,
      notice: 'أُضيف $added صنف منخفض المخزون للقائمة',
    ));
  }

  Future<void> _onAddProduct(
    PurchasesAddProduct e,
    Emitter<PurchasesState> emit,
  ) async {
    final prod = await db.getProduct(e.productId);
    if (prod == null) return;
    final draft = List<PurchaseLineDraft>.from(state.draft);
    final i = draft.indexWhere((l) => l.productId == e.productId);
    if (i >= 0) {
      draft[i] = draft[i].copyWith(
        qty: draft[i].qty + e.qty,
        unitCost: e.unitCost,
      );
    } else {
      draft.add(PurchaseLineDraft(
        productId: prod.id,
        name: prod.name,
        barcode: prod.barcode,
        qty: e.qty,
        unitCost: e.unitCost,
      ));
    }
    emit(state.copyWith(draft: draft, notice: 'أُضيف «${prod.name}» للقائمة'));
  }

  void _onUpdateLine(
    PurchasesUpdateLine e,
    Emitter<PurchasesState> emit,
  ) {
    if (e.qty <= 0) {
      emit(state.copyWith(
        draft: state.draft
            .where((l) => l.productId != e.productId)
            .toList(),
      ));
      return;
    }
    emit(state.copyWith(
      draft: state.draft
          .map((l) => l.productId == e.productId
              ? l.copyWith(qty: e.qty, unitCost: e.unitCost)
              : l)
          .toList(),
    ));
  }

  void _onRemoveLine(
    PurchasesRemoveLine e,
    Emitter<PurchasesState> emit,
  ) {
    emit(state.copyWith(
      draft:
          state.draft.where((l) => l.productId != e.productId).toList(),
    ));
  }

  Future<void> _onSaveOrder(
    PurchasesSaveOrder e,
    Emitter<PurchasesState> emit,
  ) async {
    if (state.draft.isEmpty) {
      emit(state.copyWith(
        status: PurchasesStatus.failure,
        error: 'القائمة فارغة — أضف أصنافاً أولاً',
      ));
      emit(state.copyWith(status: PurchasesStatus.ready, error: null));
      return;
    }
    emit(state.copyWith(status: PurchasesStatus.saving));
    try {
      final now = DateTime.now();
      var attempt = 0;
      var poNo = nextPoNumber(now);
      while (attempt < 5 && await db.poNumberExists(poNo)) {
        attempt++;
        poNo = nextPoNumber(now, attempt);
      }
      await db.createPurchaseOrder(
        poNumber: poNo,
        supplierName: state.supplierName.trim().isEmpty
            ? '—'
            : state.supplierName.trim(),
        supplierPhone: state.supplierPhone.trim().isEmpty
            ? null
            : state.supplierPhone.trim(),
        items: [
          for (final l in state.draft)
            PurchaseOrderItemsCompanion(
              productId: Value(l.productId),
              qtyOrdered: Value(l.qty),
              unitCost: Value(l.unitCost),
            ),
        ],
      );
      emit(state.copyWith(
        status: PurchasesStatus.ready,
        draft: [],
        saved: await _loadSaved(),
        notice: 'تم حفظ أمر الشراء $poNo',
      ));
    } catch (_) {
      emit(state.copyWith(
        status: PurchasesStatus.failure,
        error: 'تعذر حفظ أمر الشراء',
      ));
      emit(state.copyWith(status: PurchasesStatus.ready, error: null));
    }
  }

  Future<void> _onReceive(
    PurchasesReceiveOrder e,
    Emitter<PurchasesState> emit,
  ) async {
    try {
      await db.receivePurchaseOrder(e.id);
      emit(state.copyWith(
        saved: await _loadSaved(),
        notice: 'تم الاستلام وتحديث المخزون',
      ));
    } catch (_) {
      emit(state.copyWith(
        status: PurchasesStatus.failure,
        error: 'تعذر تسجيل الاستلام',
      ));
      emit(state.copyWith(status: PurchasesStatus.ready, error: null));
    }
  }

  Future<void> _onDelete(
    PurchasesDeleteOrder e,
    Emitter<PurchasesState> emit,
  ) async {
    await db.deletePurchaseOrder(e.id);
    emit(state.copyWith(
      saved: await _loadSaved(),
      notice: 'تم حذف أمر الشراء',
    ));
  }
}
