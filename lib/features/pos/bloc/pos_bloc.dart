import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// كيانات خفيفة للـ POS (تُغذّى من Drift لاحقاً عبر Repository)
class ProductDto extends Equatable {
  final int id;
  final String name;
  final String barcode;
  final double price;
  final int stockQty;
  final String? imagePath;

  const ProductDto({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stockQty,
    this.imagePath,
  });

  @override
  List<Object?> get props => [id, name, barcode, price, stockQty];
}

class CartLine extends Equatable {
  final ProductDto product;
  final int qty;
  const CartLine({required this.product, required this.qty});
  double get total => product.price * qty;

  CartLine copyWith({int? qty}) =>
      CartLine(product: product, qty: qty ?? this.qty);

  @override
  List<Object?> get props => [product, qty];
}

/// مصدر الأصناف — يُستبدل بـ Drift لاحقاً بدون تغيير البلوك
abstract class PosCatalogRepository {
  Future<List<ProductDto>> search(String query);
  Future<ProductDto?> findByBarcode(String barcode);
  Future<List<ProductDto>> favorites();
}

/// حفظ البيع (فاتورة + خصم مخزون) — يُستبدل بـ Drift في النسخة الحقيقية
abstract class PosCheckoutRepository {
  Future<({String invoiceNumber, double total})> checkout(
    List<CartLine> cart,
    double amountPaid,
  );
}

/// نسخة تجريبية للاختبارات (بدون قاعدة بيانات)
class DemoCheckoutRepository implements PosCheckoutRepository {
  int _seq = 1;

  @override
  Future<({String invoiceNumber, double total})> checkout(
    List<CartLine> cart,
    double amountPaid,
  ) async {
    final total = cart.fold<double>(0, (s, e) => s + e.total);
    final now = DateTime.now();
    final invNo =
        'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(_seq++).toString().padLeft(4, '0')}';
    return (invoiceNumber: invNo, total: total);
  }
}

/// بيانات تجريبية حتى تُولّد قاعدة Drift (build_runner)
class DemoCatalogRepository implements PosCatalogRepository {
  final List<ProductDto> _all = const [
    ProductDto(id: 1, name: 'كراسة 100 ورقة', barcode: '100001', price: 25, stockQty: 120),
    ProductDto(id: 2, name: 'قلم جاف أزرق', barcode: '100002', price: 8, stockQty: 500),
    ProductDto(id: 3, name: 'علبة ألوان 12', barcode: '100003', price: 65, stockQty: 40),
    ProductDto(id: 4, name: 'شنطة مدرسية', barcode: '100004', price: 450, stockQty: 15),
    ProductDto(id: 5, name: 'مسطرة 30 سم', barcode: '100005', price: 12, stockQty: 200),
    ProductDto(id: 6, name: 'كتاب خارجي رياضيات', barcode: '100006', price: 120, stockQty: 30),
  ];

  @override
  Future<List<ProductDto>> search(String query) async {
    await Future.delayed(const Duration(milliseconds: 120));
    if (query.trim().isEmpty) return _all;
    final q = query.trim();
    return _all
        .where((p) => p.name.contains(q) || p.barcode.contains(q))
        .toList();
  }

  @override
  Future<ProductDto?> findByBarcode(String barcode) async {
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      return _all.firstWhere((p) => p.barcode == barcode.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ProductDto>> favorites() async => [];
}

// ── Events ────────────────────────────────────────────────
sealed class PosEvent extends Equatable {
  const PosEvent();
  @override
  List<Object?> get props => [];
}

class PosStarted extends PosEvent {}

class PosQueryChanged extends PosEvent {
  final String query;
  const PosQueryChanged(this.query);
  @override
  List<Object?> get props => [query];
}

class PosBarcodeScanned extends PosEvent {
  final String code;
  const PosBarcodeScanned(this.code);
  @override
  List<Object?> get props => [code];
}

class PosAddProduct extends PosEvent {
  final ProductDto product;
  const PosAddProduct(this.product);
  @override
  List<Object?> get props => [product];
}

class PosIncrement extends PosEvent {
  final int productId;
  const PosIncrement(this.productId);
  @override
  List<Object?> get props => [productId];
}

class PosDecrement extends PosEvent {
  final int productId;
  const PosDecrement(this.productId);
  @override
  List<Object?> get props => [productId];
}

class PosRemoveLine extends PosEvent {
  final int productId;
  const PosRemoveLine(this.productId);
  @override
  List<Object?> get props => [productId];
}

class PosClearCart extends PosEvent {}

class PosCheckout extends PosEvent {
  final double amountPaid;
  const PosCheckout(this.amountPaid);
  @override
  List<Object?> get props => [amountPaid];
}

class PosCheckoutHandled extends PosEvent {}

class PosFavoritesRefreshed extends PosEvent {}

// ── State ─────────────────────────────────────────────────
enum PosStatus { initial, loading, ready, checkoutSuccess, failure }

class PosState extends Equatable {
  final PosStatus status;
  final String query;
  final List<ProductDto> catalog;
  final List<CartLine> cart;
  final String? error;
  final String? lastInvoiceNumber;
  final double? lastTotal;
  final List<CartLine> lastLines;
  final double lastAmountPaid;
  final List<ProductDto> favorites; // أزرار الاختصار المثبتة

  const PosState({
    this.status = PosStatus.initial,
    this.query = '',
    this.catalog = const [],
    this.cart = const [],
    this.error,
    this.lastInvoiceNumber,
    this.lastTotal,
    this.lastLines = const [],
    this.lastAmountPaid = 0,
    this.favorites = const [],
  });

  double get total => cart.fold(0, (s, e) => s + e.total);
  int get itemCount => cart.fold(0, (s, e) => s + e.qty);

  PosState copyWith({
    PosStatus? status,
    String? query,
    List<ProductDto>? catalog,
    List<CartLine>? cart,
    String? error,
    String? lastInvoiceNumber,
    double? lastTotal,
    List<CartLine>? lastLines,
    double? lastAmountPaid,
    List<ProductDto>? favorites,
  }) {
    return PosState(
      status: status ?? this.status,
      query: query ?? this.query,
      catalog: catalog ?? this.catalog,
      cart: cart ?? this.cart,
      error: error,
      lastInvoiceNumber: lastInvoiceNumber ?? this.lastInvoiceNumber,
      lastTotal: lastTotal ?? this.lastTotal,
      lastLines: lastLines ?? this.lastLines,
      lastAmountPaid: lastAmountPaid ?? this.lastAmountPaid,
      favorites: favorites ?? this.favorites,
    );
  }

  @override
  List<Object?> get props => [
        status,
        query,
        catalog,
        cart,
        error,
        lastInvoiceNumber,
        lastTotal,
        lastLines,
        lastAmountPaid,
        favorites,
      ];
}

// ── Bloc ──────────────────────────────────────────────────
class PosBloc extends Bloc<PosEvent, PosState> {
  final PosCatalogRepository repo;
  final PosCheckoutRepository checkoutRepo;

  PosBloc({required this.repo, required this.checkoutRepo})
      : super(const PosState()) {
    on<PosStarted>(_onStarted);
    on<PosQueryChanged>(_onQuery);
    on<PosBarcodeScanned>(_onBarcode);
    on<PosAddProduct>(_onAdd);
    on<PosIncrement>(_onInc);
    on<PosDecrement>(_onDec);
    on<PosRemoveLine>(_onRemove);
    on<PosClearCart>((e, emit) => emit(state.copyWith(cart: [])));
    on<PosCheckout>(_onCheckout);
    on<PosFavoritesRefreshed>(_onFavorites);
    on<PosCheckoutHandled>(
      (e, emit) => emit(state.copyWith(status: PosStatus.ready)),
    );
  }

  Future<void> _onStarted(PosStarted e, Emitter<PosState> emit) async {
    emit(state.copyWith(status: PosStatus.loading));
    final items = await repo.search('');
    final favs = await repo.favorites();
    emit(state.copyWith(
      status: PosStatus.ready,
      catalog: items,
      favorites: favs,
    ));
  }

  Future<void> _onFavorites(
    PosFavoritesRefreshed e,
    Emitter<PosState> emit,
  ) async {
    emit(state.copyWith(favorites: await repo.favorites()));
  }

  Future<void> _onQuery(
    PosQueryChanged e,
    Emitter<PosState> emit,
  ) async {
    emit(state.copyWith(query: e.query));
    final items = await repo.search(e.query);
    emit(state.copyWith(catalog: items));
  }

  Future<void> _onBarcode(
    PosBarcodeScanned e,
    Emitter<PosState> emit,
  ) async {
    final product = await repo.findByBarcode(e.code);
    if (product == null) {
      emit(state.copyWith(
        status: PosStatus.failure,
        error: 'لم يتم العثور على صنف بالباركود: ${e.code}',
      ));
      emit(state.copyWith(status: PosStatus.ready, error: null));
      return;
    }
    add(PosAddProduct(product));
  }

  void _onAdd(PosAddProduct e, Emitter<PosState> emit) {
    final cart = List<CartLine>.from(state.cart);
    final i = cart.indexWhere((l) => l.product.id == e.product.id);
    if (i >= 0) {
      cart[i] = cart[i].copyWith(qty: cart[i].qty + 1);
    } else {
      cart.add(CartLine(product: e.product, qty: 1));
    }
    emit(state.copyWith(cart: cart));
  }

  void _onInc(PosIncrement e, Emitter<PosState> emit) {
    final cart = state.cart
        .map((l) => l.product.id == e.productId
            ? l.copyWith(qty: l.qty + 1)
            : l)
        .toList();
    emit(state.copyWith(cart: cart));
  }

  void _onDec(PosDecrement e, Emitter<PosState> emit) {
    final cart = <CartLine>[];
    for (final l in state.cart) {
      if (l.product.id != e.productId) {
        cart.add(l);
      } else if (l.qty > 1) {
        cart.add(l.copyWith(qty: l.qty - 1));
      }
      // qty == 1 + نقصان = حذف السطر
    }
    emit(state.copyWith(cart: cart));
  }

  void _onRemove(PosRemoveLine e, Emitter<PosState> emit) {
    emit(state.copyWith(
      cart: state.cart.where((l) => l.product.id != e.productId).toList(),
    ));
  }

  Future<void> _onCheckout(PosCheckout e, Emitter<PosState> emit) async {
    if (state.cart.isEmpty) {
      emit(state.copyWith(
        status: PosStatus.failure,
        error: 'السلة فارغة — أضف صنفاً أولاً',
      ));
      emit(state.copyWith(status: PosStatus.ready, error: null));
      return;
    }
    if (e.amountPaid < state.total) {
      emit(state.copyWith(
        status: PosStatus.failure,
        error: 'المبلغ المدفوع أقل من الإجمالي',
      ));
      emit(state.copyWith(status: PosStatus.ready, error: null));
      return;
    }
    final lines = List<CartLine>.from(state.cart);
    try {
      final result = await checkoutRepo.checkout(lines, e.amountPaid);
      emit(state.copyWith(
        status: PosStatus.checkoutSuccess,
        lastInvoiceNumber: result.invoiceNumber,
        lastTotal: result.total,
        lastLines: lines,
        lastAmountPaid: e.amountPaid,
        cart: [],
      ));
    } catch (_) {
      emit(state.copyWith(
        status: PosStatus.failure,
        error: 'تعذر حفظ الفاتورة — حاول مجدداً',
      ));
      emit(state.copyWith(status: PosStatus.ready, error: null));
    }
  }
}
