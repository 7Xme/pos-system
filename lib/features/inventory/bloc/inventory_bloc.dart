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

  /// كل باركودات المنتج (الرئيسي أولاً).
  final List<String> barcodes;

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
    this.barcodes = const [],
  });

  /// عدد الباركودات الإضافية غير الرئيسية.
  int get extraBarcodesCount =>
      (barcodes.isEmpty ? 1 : barcodes.length) - 1;

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
        barcodes,
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

  /// كل الباركودات — الأول هو الرئيسي. فارغة = استخدم [barcode] فقط.
  final List<String> barcodes;

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
    this.barcodes = const [],
  });

  /// القائمة الفعلية للباركودات (مع ضمان أن الأول = [barcode]).
  List<String> get allBarcodes {
    final list = <String>[];
    for (final b in barcodes) {
      final t = b.trim();
      if (t.isNotEmpty && !list.contains(t)) list.add(t);
    }
    final primary = barcode.trim();
    if (primary.isNotEmpty && !list.contains(primary)) list.insert(0, primary);
    return list;
  }

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
        barcodes,
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

/// تحميل الصفحة التالية من المنتجات (تمرير لأسفل في الشبكة).
class InventoryLoadMore extends InventoryEvent {}

/// عدّاد المخزون المنخفض فقط — استعلام خفيف لا يحمّل الكتالوج (شارة القائمة).
class InventoryLowStockCountRequested extends InventoryEvent {}

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
  final List<InventoryProduct> products; // الصفحات المحمّلة بعد الفلاتر
  final List<InventoryProduct> favoriteProducts; // كل المثبتة (للاختصارات)
  final List<InventoryCategory> categories;
  final int lowStockCount;
  final String query;
  final int? categoryFilterId;
  final bool lowStockOnly;
  final String? error;
  final String? notice;

  /// العدد الكلي المطابق للفلاتر في القاعدة (لبقية الصفحات).
  final int totalCount;

  /// هل توجد صفحات أخرى لم تُحمَّل بعد؟
  final bool hasMore;

  /// جارٍ تحميل الصفحة التالية.
  final bool loadingMore;

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
    this.totalCount = 0,
    this.hasMore = false,
    this.loadingMore = false,
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
    int? totalCount,
    bool? hasMore,
    bool? loadingMore,
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
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
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
        totalCount,
        hasMore,
        loadingMore,
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final AppDatabase db;

  /// حجم الصفحة الواحدة — شبكة المخزون تعرض 4 أعمدة، فالصفحة تكفي عدة
  /// شاشات، وتُحمَّل التالية عند التمرير.
  static const int _pageSize = 120;

  InventoryBloc({required this.db}) : super(const InventoryState()) {
    on<InventoryStarted>(_onStarted);
    on<InventoryQueryChanged>(_onFilter);
    on<InventoryCategorySelected>(_onFilter);
    on<InventoryLowStockToggled>(_onFilter);
    on<InventoryLoadMore>(_onLoadMore);
    on<InventoryLowStockCountRequested>(_onLowStockCountRequested);
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
    if (state.status == InventoryStatus.initial) {
      emit(state.copyWith(status: InventoryStatus.loading));
    }
    await _reload(emit);
  }

  /// يحمّل الصفحة الأولى + بيانات الشاشة المساعدة (فئات، مثبتة، عدّادات).
  Future<void> _reload(Emitter<InventoryState> emit) async {
    final categories = await db.allCategories();
    final counts = await db.productCountByCategory();
    final catNames = {for (final c in categories) c.id: c.name};

    final page = await _fetchPage(
      query: state.query,
      categoryId: state.categoryFilterId,
      lowStockOnly: state.lowStockOnly,
      catNames: catNames,
    );

    final favRows = await db.favoriteProducts();
    final favIds = [for (final p in favRows) p.id];
    final favBarcodes = await db.barcodesOfAll(favIds);
    final favHistory = await db.productIdsWithHistory(ids: favIds);

    final lowCount = await db.lowStockProductCount();

    final favorites = [
      for (final p in favRows)
        _toInventoryProduct(
          p,
          barcodes: favBarcodes[p.id],
          hasHistory: favHistory.contains(p.id),
          categoryName: catNames[p.categoryId],
        ),
    ];

    emit(
      state.copyWith(
        status: InventoryStatus.ready,
        products: page.items,
        favoriteProducts: favorites,
        categories: [
          for (final c in categories)
            InventoryCategory(
              id: c.id,
              name: c.name,
              productCount: counts[c.id] ?? 0,
            ),
        ],
        lowStockCount: lowCount,
        totalCount: page.total,
        hasMore: page.items.length < page.total,
        loadingMore: false,
        error: null,
        notice: null,
      ),
    );
  }

  /// يجلب صفحة منتجات (وباركوداتها/سجلها) فقط — بلا الفئات أو العدّادات.
  /// تُستعمل عند تغيير البحث/الفلتر وعند التمرير، حيث لا تتغيّر بيانات الشاشة.
  Future<({List<InventoryProduct> items, int total})> _fetchPage({
    required String query,
    required int? categoryId,
    required bool lowStockOnly,
    required Map<int, String> catNames,
    int offset = 0,
  }) async {
    final page = await db.searchInventoryPage(
      query: query,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      limit: _pageSize,
      offset: offset,
    );
    final ids = [for (final p in page.items) p.id];
    final barcodes = await db.barcodesOfAll(ids);
    final history = await db.productIdsWithHistory(ids: ids);
    return (
      items: [
        for (final p in page.items)
          _toInventoryProduct(
            p,
            barcodes: barcodes[p.id],
            hasHistory: history.contains(p.id),
            categoryName: catNames[p.categoryId],
          ),
      ],
      total: page.total,
    );
  }

  InventoryProduct _toInventoryProduct(
    Product p, {
    List<String>? barcodes,
    bool hasHistory = false,
    String? categoryName,
  }) {
    return InventoryProduct(
      id: p.id,
      name: p.name,
      barcode: p.barcode,
      price: p.price,
      cost: p.cost,
      stockQty: p.stockQty,
      minStock: p.minStock,
      imagePath: p.imagePath,
      categoryId: p.categoryId,
      categoryName: categoryName,
      isActive: p.isActive,
      isFavorite: p.isFavorite,
      hasHistory: hasHistory,
      barcodes: barcodes ??
          [if (p.barcode.trim().isNotEmpty) p.barcode],
    );
  }

  /// تحميل صفحة إضافية عند التمرير لأسفل.
  Future<void> _onLoadMore(
    InventoryLoadMore e,
    Emitter<InventoryState> emit,
  ) async {
    if (state.loadingMore || !state.hasMore) return;
    final query = state.query;
    final categoryId = state.categoryFilterId;
    final lowStockOnly = state.lowStockOnly;
    emit(state.copyWith(loadingMore: true));

    final page = await _fetchPage(
      query: query,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      catNames: {for (final c in state.categories) c.id: c.name},
      offset: state.products.length,
    );
    // تغيّر الفلتر أثناء الجلب: تجاهل الصفحة القديمة.
    if (state.query != query ||
        state.categoryFilterId != categoryId ||
        state.lowStockOnly != lowStockOnly) {
      emit(state.copyWith(loadingMore: false));
      return;
    }
    final merged = [...state.products, ...page.items];
    emit(state.copyWith(
      products: merged,
      totalCount: page.total,
      hasMore: merged.length < page.total,
      loadingMore: false,
    ));
  }

  Future<void> _onLowStockCountRequested(
    InventoryLowStockCountRequested e,
    Emitter<InventoryState> emit,
  ) async {
    emit(state.copyWith(lowStockCount: await db.lowStockProductCount()));
  }

  /// تغيير البحث/الفلتر: يجلب الصفحة الأولى فقط — الفئات والعدّادات والمثبتة
  /// لا تتغيّر بتغيّر الفلتر، فلا داعي لإعادة قراءتها مع كل ضغطة مفتاح.
  Future<void> _onFilter(
    InventoryEvent e,
    Emitter<InventoryState> emit,
  ) async {
    if (e is InventoryQueryChanged) {
      emit(state.copyWith(query: e.query));
    } else if (e is InventoryCategorySelected) {
      emit(state.copyWith(categoryFilterId: () => e.categoryId));
    } else if (e is InventoryLowStockToggled) {
      emit(state.copyWith(lowStockOnly: e.only));
    }
    final query = state.query;
    final categoryId = state.categoryFilterId;
    final lowStockOnly = state.lowStockOnly;
    final page = await _fetchPage(
      query: query,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      catNames: {for (final c in state.categories) c.id: c.name},
    );
    // تغيّر الفلتر أثناء الجلب: النتيجة القديمة لا تصلح للعرض.
    if (state.query != query ||
        state.categoryFilterId != categoryId ||
        state.lowStockOnly != lowStockOnly) {
      return;
    }
    emit(state.copyWith(
      products: page.items,
      totalCount: page.total,
      hasMore: page.items.length < page.total,
      loadingMore: false,
    ));
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
        await db.insertProductWithBarcodes(
          ProductsCompanion.insert(
            name: d.name,
            barcode: d.allBarcodes.isEmpty ? d.barcode : d.allBarcodes.first,
            price: d.price,
            cost: Value(d.cost),
            stockQty: Value(d.stockQty),
            minStock: Value(d.minStock),
            categoryId: Value(d.categoryId),
            imagePath: Value(imagePath),
            isActive: Value(d.isActive),
          ),
          d.allBarcodes,
        );
        emit(state.copyWith(
          status: InventoryStatus.ready,
          notice: 'تمت إضافة «${d.name}» بنجاح',
        ));
      } else {
        final all = d.allBarcodes;
        await db.updateProduct(
          d.id!,
          ProductsCompanion(
            name: Value(d.name),
            barcode: Value(all.isEmpty ? d.barcode : all.first),
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
        await db.setProductBarcodes(d.id!, all);
        emit(state.copyWith(
          status: InventoryStatus.ready,
          notice: 'تم حفظ تعديلات «${d.name}»',
        ));
      }
      await _reload(emit);
      emit(state.copyWith(notice: 'تم الحفظ بنجاح'));
    } catch (err) {
      final msg = err is StateError && err.message.toString().isNotEmpty
          ? err.message.toString()
          : 'تعذر الحفظ — تأكد أن الباركود غير مستخدم لمنتج آخر';
      emit(state.copyWith(
        status: InventoryStatus.failure,
        error: msg,
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
