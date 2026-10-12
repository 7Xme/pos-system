import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';

/// نموذج إضافة سريعة لصنف مجهول الباركود.
///
/// يُفتح من شاشة البيع عند مسح باركود غير موجود في القاعدة، مع تعبئة
/// الباركود تلقائياً. يقبل الاسم + سعر البيع + الكمية فقط، والباقي
/// يُترك للافتراضي (سعر الشراء 0، حد التنبيه 5، بلا فئة، نشط).
///
/// يُرجع اسم المنتج عند الحفظ، أو null عند الإلغاء.
Future<String?> showQuickAddProductDialog(
  BuildContext context, {
  required String barcode,
  required AppDatabase db,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuickAddProductDialog(barcode: barcode, db: db),
  );
}

class _QuickAddProductDialog extends StatefulWidget {
  final String barcode;
  final AppDatabase db;
  const _QuickAddProductDialog({required this.barcode, required this.db});

  @override
  State<_QuickAddProductDialog> createState() =>
      _QuickAddProductDialogState();
}

class _QuickAddProductDialogState extends State<_QuickAddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) {
      setState(() => _formError = 'سعر البيع غير صالح');
      return;
    }
    var qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty < 0) qty = 0;

    setState(() => _saving = true);
    try {
      await widget.db.insertProduct(
        ProductsCompanion.insert(
          name: name,
          barcode: widget.barcode,
          price: price,
          stockQty: Value(qty),
        ),
      );
      if (mounted) Navigator.pop(context, name);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'تعذر الحفظ — الباركود مستخدم لمنتج آخر على الأرجح';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_box_outlined),
          SizedBox(width: 8),
          Text('منتج جديد'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الباركود غير موجود في القاعدة — أضِفه الآن '
                  'ليصبح متاحاً للبيع مستقبلاً.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // الباركود (مقروء فقط — مأخوذ من المسح)
                TextFormField(
                  initialValue: widget.barcode,
                  readOnly: true,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'الباركود',
                    prefixIcon: Icon(Icons.qr_code_2),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'اسم المنتج *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          labelText: 'سعر البيع *',
                          prefixIcon: Icon(Icons.sell_outlined),
                        ),
                        validator: (v) =>
                            double.tryParse((v ?? '').trim()) == null
                                ? 'سعر غير صالح'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          labelText: 'الكمية',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _formError!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        SizedBox(
          height: 52,
          child: TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('إضافة المنتج'),
          ),
        ),
      ],
    );
  }
}
