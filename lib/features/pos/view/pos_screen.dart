import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/barcode/barcode_scanner_service.dart';
import '../../../core/printing/a4_print_service.dart';
import '../../../core/printing/pdf_builders.dart';
import '../../../core/tts/arabic_tts_service.dart';
import '../../settings/bloc/settings_cubit.dart';
import '../bloc/pos_bloc.dart';

/// الخطوة 3: واجهة نقطة البيع الرئيسية
/// - بحث + مسح باركود (HID كلوحة مفاتيح + حقل يدوي)
/// - أزرار لمس كبيرة ≥ 56px، بدون اعتماد على Hover
/// - RTL كامل عبر MaterialApp (locale: ar)
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _barcodeNode = FocusNode();
  StreamSubscription<String>? _barcodeSub;
  Timer? _debounce;

  /// يعيد الفوكس لحقل الباركود ليبقى الماسح/الكتابة جاهزين دائماً.
  void _refocusBarcode() {
    if (!mounted) return;
    if (!BarcodeScannerService.captureEnabled) return;
    _barcodeNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    context.read<PosBloc>().add(PosStarted());
    // التقاط الماسح عاماً من أي مكان (يعمل دون نقر أي حقل)
    BarcodeScannerService.captureEnabled = true;
    HardwareKeyboard.instance.addHandler(BarcodeScannerService.handleKey);
    // زر Enter العام = إتمام البيع (ما لم يكن مسحاً أو كتابة نص)
    BarcodeScannerService.onCheckoutHotkey = () {
      if (!mounted) return;
      _checkout(context.read<PosBloc>().state);
    };
    _barcodeSub = BarcodeScannerService.stream.listen((code) {
      if (!mounted) return;
      context.read<PosBloc>().add(PosBarcodeScanned(code));
      _barcodeCtrl.clear();
      _refocusBarcode();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _barcodeCtrl.dispose();
    _paidCtrl.dispose();
    _barcodeNode.dispose();
    HardwareKeyboard.instance
        .removeHandler(BarcodeScannerService.handleKey);
    BarcodeScannerService.onCheckoutHotkey = null;
    _barcodeSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) context.read<PosBloc>().add(PosQueryChanged(v));
    });
  }

  Future<void> _checkout(PosState state) async {
    final paid = double.tryParse(_paidCtrl.text.trim()) ?? state.total;
    context.read<PosBloc>().add(PosCheckout(paid));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosBloc, PosState>(
      listenWhen: (a, b) =>
          a.status != b.status || a.lastInvoiceNumber != b.lastInvoiceNumber,
      listener: (context, state) async {
        if (state.status == PosStatus.failure && state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!)),
          );
        }
        if (state.status == PosStatus.checkoutSuccess) {
          final total = state.lastTotal ?? 0;
          final invNo = state.lastInvoiceNumber ?? '';
          final settings = context.read<SettingsCubit>().state;
          // 1) نطق المجموع بالعربية — حسب الإعدادات
          var spoken = true;
          if (settings.soundEnabled) {
            spoken = await ArabicTtsService.instance.speakTotal(
              total,
              currency: settings.currency,
              source: settings.ttsSource,
            );
          }
          // 2) طباعة A4 — حسب الإعدادات (بسطور الفاتورة المحفوظة)
          if (settings.autoPrint) {
            List<int>? logoBytes;
            final logoPath = settings.logoPath;
            try {
              if (logoPath != null && File(logoPath).existsSync()) {
                logoBytes = await File(logoPath).readAsBytes();
              }
            } catch (_) {
              logoBytes = null;
            }
            final phone =
                settings.phone.isEmpty ? null : settings.phone;
            await A4PrintService.printInvoice(
              shopName: settings.shopName,
              invoiceNumber: invNo,
              date: DateTime.now(),
              lines: [
                for (final l in state.lastLines)
                  InvoiceLine(
                    name: l.product.name,
                    qty: l.qty,
                    unitPrice: l.product.price,
                  ),
              ],
              amountPaid: state.lastAmountPaid,
              cashier: settings.cashier,
              currency: settings.currency,
              phone: phone,
              logoBytes: logoBytes,
            );
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  spoken
                      ? 'تم البيع $invNo — الإجمالي $total'
                      : 'تم البيع $invNo — تعذر النطق الصوتي، راجع اختبار الصوت في الإعدادات',
                ),
              ),
            );
            _paidCtrl.clear();
            context.read<PosBloc>().add(PosCheckoutHandled());
            _refocusBarcode();
          }
        }
      },
      builder: (context, state) {
        final currency = context.select<SettingsCubit, String>(
          (c) => c.state.currency,
        );
        return Scaffold(
            appBar: AppBar(
              title: const Text('نقطة البيع — مكتبة'),
              actions: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'الأصناف: ${state.itemCount}  |  الإجمالي: ${state.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: Row(
              children: [
                // ── يمين: البحث + الشبكة (في RTL أول عنصر يظهر يمين) ──
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // بحث كبير للمس
                        SizedBox(
                          height: 60,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _refocusBarcode(),
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(fontSize: 18),
                            decoration: const InputDecoration(
                              hintText: 'ابحث بالاسم أو الباركود...',
                              prefixIcon: Icon(Icons.search, size: 28),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // حقل الباركود اليدوي (للماسح HID يكفي Enter)
                        SizedBox(
                          height: 60,
                          child: TextField(
                            key: const Key('barcodeField'),
                            controller: _barcodeCtrl,
                            focusNode: _barcodeNode,
                            autofocus: true,
                            onSubmitted: (v) {
                              if (v.trim().isEmpty) {
                                // Enter على حقل فارغ = إتمام البيع
                                _checkout(
                                  context.read<PosBloc>().state,
                                );
                                _refocusBarcode();
                                return;
                              }
                              context
                                  .read<PosBloc>()
                                  .add(PosBarcodeScanned(v));
                              _barcodeCtrl.clear();
                              _refocusBarcode();
                            },
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              hintText: 'امسح الباركود هنا أو اكتبه ثم Enter',
                              prefixIcon: const Icon(
                                Icons.barcode_reader,
                                size: 28,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.add, size: 28),
                                onPressed: () {
                                  context.read<PosBloc>().add(
                                        PosBarcodeScanned(
                                          _barcodeCtrl.text,
                                        ),
                                      );
                                  _barcodeCtrl.clear();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // شريط أزرار الاختصار (المنتجات المثبتة ★)
                        if (state.favorites.isNotEmpty) ...[
                          SizedBox(
                            height: 60,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: state.favorites.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final p = state.favorites[i];
                                return SizedBox(
                                  height: 60,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => context
                                        .read<PosBloc>()
                                        .add(PosAddProduct(p)),
                                    icon: const Icon(
                                      Icons.star,
                                      size: 22,
                                    ),
                                    label: Text(
                                      '${p.name} — ${p.price.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: state.status == PosStatus.loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : state.catalog.isEmpty
                                  ? _emptyCatalog(
                                      onClear: () {
                                        _searchCtrl.clear();
                                        context
                                            .read<PosBloc>()
                                            .add(const PosQueryChanged(''));
                                      },
                                    )
                                  : GridView.builder(
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 0.82,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                      itemCount: state.catalog.length,
                                      itemBuilder: (ctx, i) {
                                        final p = state.catalog[i];
                                        return _ProductCard(
                                          name: p.name,
                                          price: p.price,
                                          stock: p.stockQty,
                                          currency: currency,
                                          imagePath: p.imagePath,
                                          onAdd: () => context
                                              .read<PosBloc>()
                                              .add(PosAddProduct(p)),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // ── يسار: السلة ──
                SizedBox(
                  width: 400,
                  child: _CartPanel(
                    state: state,
                    paidCtrl: _paidCtrl,
                    onCheckout: () => _checkout(state),
                  ),
                ),
              ],
            ),
          );
      },
    );
  }

  Widget _emptyCatalog({required VoidCallback onClear}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 12),
          const Text('لا توجد أصناف مطابقة',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: onClear,
            child: const Text('عرض الكل'),
          ),
        ],
      ),
    );
  }
}

/// بطاقة صنف — زر إضافة ضخم للمس + صورة المنتج
class _ProductCard extends StatelessWidget {
  final String name;
  final double price;
  final int stock;
  final String currency;
  final String? imagePath;
  final VoidCallback onAdd;

  const _ProductCard({
    required this.name,
    required this.price,
    required this.stock,
    required this.currency,
    this.imagePath,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final low = stock <= 5;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd, // كامل البطاقة قابل للمس — لا Hover
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 64,
                width: 64,
                child: _ProductThumb(path: imagePath),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '${price.toStringAsFixed(2)} $currency',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                low ? 'مخزون منخفض: $stock' : 'متاح: $stock',
                style: TextStyle(
                  fontSize: 13,
                  color: low ? Colors.red : Colors.green[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_shopping_cart, size: 24),
                  label: const Text('أضف'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مصغرة صورة المنتج — أيقونة افتراضية عند غياب الصورة
class _ProductThumb extends StatelessWidget {
  final String? path;
  const _ProductThumb({this.path});

  @override
  Widget build(BuildContext context) {
    if (path != null && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.image_outlined,
        size: 32,
        color: Colors.grey,
      ),
    );
  }
}

/// لوحة السلة — أزرار + و − بحجم لمس
class _CartPanel extends StatelessWidget {
  final PosState state;
  final TextEditingController paidCtrl;
  final VoidCallback onCheckout;

  const _CartPanel({
    required this.state,
    required this.paidCtrl,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final currency = context.select<SettingsCubit, String>(
      (c) => c.state.currency,
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'السلة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.cart.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 56),
                        SizedBox(height: 8),
                        Text('السلة فارغة — امسح صنفاً للبدء'),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: state.cart.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final line = state.cart[i];
                      return _CartLineTile(line: line);
                    },
                  ),
          ),
          const Divider(),
          // الإجمالي بخط ضخم
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF2A007)),
            ),
            child: Text(
              'الإجمالي: ${state.total.toStringAsFixed(2)} $currency',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: TextField(
              controller: paidCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onCheckout(),
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'المبلغ المدفوع (افتراضي = الإجمالي)',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: OutlinedButton(
                    onPressed: state.cart.isEmpty
                        ? null
                        : () => context
                            .read<PosBloc>()
                            .add(PosClearCart()),
                    child: const Text('مسح'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed:
                        state.cart.isEmpty ? null : onCheckout,
                    icon: const Icon(Icons.check_circle, size: 28),
                    label: const Text(
                      'إتمام البيع + نطق وطباعة',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final CartLine line;
  const _CartLineTile({required this.line});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${line.product.price.toStringAsFixed(2)} × ${line.qty} = ${line.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          // stepper لمس
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filledTonal(
              onPressed: () => context
                  .read<PosBloc>()
                  .add(PosIncrement(line.product.id)),
              icon: const Icon(Icons.add, size: 24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${line.qty}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.outlined(
              onPressed: () => context
                  .read<PosBloc>()
                  .add(PosDecrement(line.product.id)),
              icon: const Icon(Icons.remove, size: 24),
            ),
          ),
          IconButton(
            onPressed: () => context
                .read<PosBloc>()
                .add(PosRemoveLine(line.product.id)),
            icon: const Icon(Icons.delete_outline, size: 24),
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}
