import 'dart:io';

import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/database/app_database.dart';
import '../../../core/images/product_image_store.dart';

/// منتج للعرض في شاشات المخزون
class InventoryProduct extends Equatable {
  final int id;
  final String name;
  final String barcode;
  final double price;
  final double cost;
  final int stockQty;
  final int minStock;
  final String? imagePath;
  final int? categoryId;
  final String? categoryName;
  final bool isActive;
  final bool isFavorite;

  /// له سجل مبيعات/مشتريات — لا يمكن حذفه (يمكن تعطيله).
  final bool hasHistory;

  const InventoryProduct({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.cost,
    required this.stockQty,
    required this.minStock,
    this.imagePath,
    this.categoryId,
    this.categoryName,
    required this.isActive,
    this.isFavorite = false,
    this.hasHistory = false,
  });

  bool get isLowStock => stockQty <= minStock;

  @override
  List<Object?> get props => [
        id,
        name,
        barcode,
        price,
        cost,
        stockQty,
        minStock,
        imagePath,
        categoryId,
        categoryName,
        isActive,
        isFavorite,
        hasHistory,
      ];
}

class InventoryCategory extends Equatable {
  final int id;
  final String name;
  final int productCount;

  const InventoryCategory({
    required this.id,
    required this.name,
    this.productCount = 0,
  });

  @override
  List<Object?> get props => [id, name, productCount];
}

/// مسودة منتج من النموذج (id == null يعني منتج جديد)
class ProductDraft extends Equatable {
  final int? id;
  final String name;
  final String barcode;
  final double price;
  final double cost;
  final int stockQty;
  final int minStock;
  final int? categoryId;
  final String? existingImagePath;
  final bool isActive;

  const ProductDraft({
    this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.cost,
    required this.stockQty,
    required this.minStock,
    this.categoryId,
    this.existingImagePath,
    this.isActive = true,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        barcode,
        price,
        cost,
        stockQty,
        minStock,
        categoryId,
        existingImagePath,
        isActive,
      ];
}

// ── Events ────────────────────────────────────────────────
sealed class InventoryEvent extends Equatable {
  const InventoryEvent();
  @override
  List<Object?> get props => [];
}

class InventoryStarted extends InventoryEvent {}

class InventoryQueryChanged extends InventoryEvent {
  final String query;
  const InventoryQueryChanged(this.query);
  @override
  List<Object?> get props => [query];
}

class InventoryCategorySelected extends InventoryEvent {
  final int? categoryId; // null = الكل
  const InventoryCategorySelected(this.categoryId);
  @override
  List<Object?> get props => [categoryId];
}

class InventoryLowStockToggled extends InventoryEvent {
  final bool only;
  const InventoryLowStockToggled(this.only);
  @override
  List<Object?> get props => [only];
}

class InventoryProductSaved extends InventoryEvent {
  final ProductDraft draft;
  final File? newImage;
  const InventoryProductSaved(this.draft, {this.newImage});
  @override
  List<Object?> get props => [draft];
}

class InventoryProductDeleted extends InventoryEvent {
  final int id;
  const InventoryProductDeleted(this.id);
  @override
  List<Object?> get props => [id];
}

class InventoryCategorySaved extends InventoryEvent {
  final int? id; // null = فئة جديدة
  final String name;
  const InventoryCategorySaved({this.id, required this.name});
  @override
  List<Object?> get props => [id, name];
}

class InventoryCategoryDeleted extends InventoryEvent {
  final int id;
  const InventoryCategoryDeleted(this.id);
  @override
  List<Object?> get props => [id];
}

class InventoryFavoriteToggled extends InventoryEvent {
  final int id;
  final bool favorite;
  const InventoryFavoriteToggled(this.id, this.favorite);
  @override
  List<Object?> get props => [id, favorite];
}

class InventoryNoticeShown extends InventoryEvent {}

// ── State ─────────────────────────────────────────────────
enum InventoryStatus { initial, loading, ready, saving, failure }

class InventoryState extends Equatable {
  final InventoryStatus status;
  final List<InventoryProduct> products; // بعد الفلاتر
  final List<InventoryProduct> favoriteProducts; // كل المثبتة (للاختصارات)
  final List<InventoryCategory> categories;
  final int lowStockCount;
  final String query;
  final int? categoryFilterId;
  final bool lowStockOnly;
  final String? error;
  final String? notice;

  const InventoryState({
    this.status = InventoryStatus.initial,
    this.products = const [],
    this.favoriteProducts = const [],
    this.categories = const [],
    this.lowStockCount = 0,
    this.query = '',
    this.categoryFilterId,
    this.lowStockOnly = false,
    this.error,
    this.notice,
  });

  InventoryState copyWith({
    InventoryStatus? status,
    List<InventoryProduct>? products,
    List<InventoryProduct>? favoriteProducts,
    List<InventoryCategory>? categories,
    int? lowStockCount,
    String? query,
    int? Function()? categoryFilterId,
    bool? lowStockOnly,
    String? error,
    String? notice,
  }) {
    return InventoryState(
      status: status ?? this.status,
      products: products ?? this.products,
      favoriteProducts: favoriteProducts ?? this.favoriteProducts,
      categories: categories ?? this.categories,
      lowStockCount: lowStockCount ?? this.lowStockCount,
      query: query ?? this.query,
      categoryFilterId:
          categoryFilterId != null ? categoryFilterId() : this.categoryFilterId,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      error: error,
      notice: notice,
    );
  }

  @override
  List<Object?> get props => [
        status,
        products,
        favoriteProducts,
        categories,
        lowStockCount,
        query,
        categoryFilterId,
        lowStockOnly,
        error,
        notice,
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final AppDatabase db;
  List<InventoryProduct> _all = [];

  InventoryBloc({required this.db}) : super(const InventoryState()) {
    on<InventoryStarted>(_onStarted);
    on<InventoryQueryChanged>(_onFilter);
    on<InventoryCategorySelected>(_onFilter);
    on<InventoryLowStockToggled>(_onFilter);
    on<InventoryProductSaved>(_onProductSaved);
    on<InventoryProductDeleted>(_onProductDeleted);
    on<InventoryFavoriteToggled>(_onFavoriteToggled);
    on<InventoryCategorySaved>(_onCategorySaved);
    on<InventoryCategoryDeleted>(_onCategoryDeleted);
    on<InventoryNoticeShown>(
      (e, emit) => emit(state.copyWith(status: InventoryStatus.ready)),
    );
  }

  Future<void> _onStarted(
    InventoryStarted e,
    Emitter<InventoryState> emit,
  ) async {
    emit(state.copyWith(status: InventoryStatus.loading));
    await _reload(emit);
  }

  Future<void> _reload(Emitter<InventoryState> emit) async {
    final products = await db.allProducts();
    final categories = await db.allCategories();
    final counts = await db.productCountByCategory();
    final history = await db.productIdsWithHistory();
    final catNames = {for (final c in categories) c.id: c.name};
    _all = products
        .map(
          (p) => InventoryProduct(
            id: p.id,
            name: p.name,
            barcode: p.barcode,
            price: p.price,
            cost: p.cost,
            stockQty: p.stockQty,
            minStock: p.minStock,
            imagePath: p.imagePath,
            categoryId: p.categoryId,
            categoryName:
                p.categoryId == null ? null : catNames[p.categoryId],
            isActive: p.isActive,
            isFavorite: p.isFavorite,
            hasHistory: history.contains(p.id),
          ),
        )
        .toList();
    emit(
      state.copyWith(
        status: InventoryStatus.ready,
        products: _applyFilters(),
        favoriteProducts: _all.where((p) => p.isFavorite).toList(),
        categories: categories
            .map(
              (c) => InventoryCategory(
                id: c.id,
                name: c.name,
                productCount: counts[c.id] ?? 0,
              ),
            )
            .toList(),
        lowStockCount: _all.where((p) => p.isLowStock).length,
        error: null,
        notice: null,
      ),
    );
  }

  List<InventoryProduct> _applyFilters() => _filtered();

  Future<void> _onFilter(
    InventoryEvent e,
    Emitter<InventoryState> emit,
  ) async {
    if (e is InventoryQueryChanged) {
      emit(state.copyWith(
        query: e.query,
        products: _filtered(query: e.query),
      ));
    } else if (e is InventoryCategorySelected) {
      emit(state.copyWith(
        categoryFilterId: () => e.categoryId,
        products: _filtered(cat: () => e.categoryId),
      ));
    } else if (e is InventoryLowStockToggled) {
      emit(state.copyWith(
        lowStockOnly: e.only,
        products: _filtered(lowOnly: e.only),
      ));
    }
  }

  List<InventoryProduct> _filtered({
    String? query,
    int? Function()? cat,
    bool? lowOnly,
  }) {
    final q = (query ?? state.query).trim();
    final catId = cat != null ? cat() : state.categoryFilterId;
    final low = lowOnly ?? state.lowStockOnly;
    return _all.where((p) {
      if (low && !p.isLowStock) return false;
      if (catId != null && p.categoryId != catId) return false;
      if (q.isNotEmpty && !p.name.contains(q) && !p.barcode.contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _onProductSaved(
    InventoryProductSaved e,
    Emitter<InventoryState> emit,
  ) async {
    emit(state.copyWith(status: InventoryStatus.saving));
    try {
      String? imagePath = e.draft.existingImagePath;
      if (e.newImage != null) {
        imagePath = await ProductImageStore.save(e.newImage!);
        // احذف الصورة القديمة عند الاستبدال
        if (e.draft.existingImagePath != null &&
            e.draft.existingImagePath != imagePath) {
          await ProductImageStore.deleteIfExists(e.draft.existingImagePath);
        }
      }
      final d = e.draft;
      if (d.id == null) {
        await db.insertProduct(
          ProductsCompanion.insert(
            name: d.name,
            barcode: d.barcode,
            price: d.price,
            cost: Value(d.cost),
            stockQty: Value(d.stockQty),
            minStock: Value(d.minStock),
            categoryId: Value(d.categoryId),
            imagePath: Value(imagePath),
            isActive: Value(d.isActive),
          ),
        );
        emit(state.copyWith(
          status: InventoryStatus.ready,
          notice: 'تمت إضافة «${d.name}» بنجاح',
        ));
      } else {
        await db.updateProduct(
          d.id!,
          ProductsCompanion(
            name: Value(d.name),
            barcode: Value(d.barcode),
            price: Value(d.price),
            cost: Value(d.cost),
            stockQty: Value(d.stockQty),
            minStock: Value(d.minStock),
            categoryId: Value(d.categoryId),
            imagePath: Value(imagePath),
            isActive: Value(d.isActive),
            updatedAt: Value(DateTime.now()),
          ),
        );
        emit(state.copyWith(
          status: InventoryStatus.ready,
          notice: 'تم حفظ تعديلات «${d.name}»',
        ));
      }
      await _reload(emit);
      emit(state.copyWith(notice: 'تم الحفظ بنجاح'));
    } catch (_) {
      emit(state.copyWith(
        status: InventoryStatus.failure,
        error: 'تعذر الحفظ — تأكد أن الباركود غير مستخدم لمنتج آخر',
      ));
      emit(state.copyWith(status: InventoryStatus.ready, error: null));
    }
  }

  Future<void> _onProductDeleted(
    InventoryProductDeleted e,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final target = await db.getProduct(e.id);
      // المنتج صاحب السجل لا يُحذف (المفتاح الأجنبي يمنع) — عطّله بدلاً من ذلك.
      if (await db.hasProductHistory(e.id)) {
        emit(state.copyWith(
          status: InventoryStatus.failure,
          error: 'لا يمكن حذف «${target?.name ?? ''}» — له سجل مبيعات/مشتريات. '
              'عطّله من نموذج التعديل بدلاً من ذلك',
        ));
        emit(state.copyWith(status: InventoryStatus.ready, error: null));
        return;
      }
      await db.deleteProduct(e.id);
      if (target?.imagePath != null) {
        await ProductImageStore.deleteIfExists(target!.imagePath);
      }
      await _reload(emit);
      emit(state.copyWith(notice: 'تم حذف المنتج'));
    } catch (_) {
      emit(state.copyWith(
        status: InventoryStatus.failure,
        error: 'تعذر حذف المنتج',
      ));
      emit(state.copyWith(status: InventoryStatus.ready, error: null));
    }
  }

  Future<void> _onFavoriteToggled(
    InventoryFavoriteToggled e,
    Emitter<InventoryState> emit,
  ) async {
    await db.setFavorite(e.id, e.favorite);
    await _reload(emit);
  }

  Future<void> _onCategorySaved(
    InventoryCategorySaved e,
    Emitter<InventoryState> emit,
  ) async {
    final name = e.name.trim();
    if (name.isEmpty) return;
    try {
      if (e.id == null) {
        await db.insertCategory(name);
      } else {
        await db.updateCategoryName(e.id!, name);
      }
      await _reload(emit);
      emit(state.copyWith(notice: 'تم حفظ الفئة «$name»'));
    } catch (_) {
      emit(state.copyWith(
        status: InventoryStatus.failure,
        error: 'تعذر حفظ الفئة — الاسم مستخدم على الأرجح',
      ));
      emit(state.copyWith(status: InventoryStatus.ready, error: null));
    }
  }

  Future<void> _onCategoryDeleted(
    InventoryCategoryDeleted e,
    Emitter<InventoryState> emit,
  ) async {
    try {
      // المفتاح الأجنبي NO ACTION — الفئة ذات المنتجات لا تُحذف.
      final counts = await db.productCountByCategory();
      final n = counts[e.id] ?? 0;
      if (n > 0) {
        final name =
            state.categories.where((c) => c.id == e.id).firstOrNull?.name ??
                '';
        emit(state.copyWith(
          status: InventoryStatus.failure,
          error: 'لا يمكن حذف فئة «$name» — فيها $n منتج. '
              'انقل منتجاتها لفئة أخرى أولاً',
        ));
        emit(state.copyWith(status: InventoryStatus.ready, error: null));
        return;
      }
      await db.deleteCategory(e.id);
      int? current = state.categoryFilterId;
      if (current == e.id) current = null;
      emit(state.copyWith(categoryFilterId: () => current));
      await _reload(emit);
      emit(state.copyWith(notice: 'تم حذف الفئة'));
    } catch (_) {
      emit(state.copyWith(
        status: InventoryStatus.failure,
        error: 'تعذر حذف الفئة',
      ));
      emit(state.copyWith(status: InventoryStatus.ready, error: null));
    }
  }
}
