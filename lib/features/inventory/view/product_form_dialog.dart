import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/images/product_image_store.dart';
import '../bloc/inventory_bloc.dart';

/// يعرض نموذج إضافة/تعديل منتج (product == null يعني جديد)
Future<void> showProductFormDialog(
  BuildContext context,
  InventoryProduct? product,
) {
  final bloc = context.read<InventoryBloc>();
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: _ProductFormDialog(product: product),
    ),
  );
}

class _ProductFormDialog extends StatefulWidget {
  final InventoryProduct? product;
  const _ProductFormDialog({this.product});

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final List<TextEditingController> _barcodeCtrls;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  int? _categoryId;
  bool _isActive = true;
  File? _newImage;
  bool _removeImage = false;
  String? _formError;

  bool get isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    // كل باركود في سطر — السطر الأول هو الرئيسي
    final initial = <String>[
      if (p != null && p.barcodes.isNotEmpty) ...p.barcodes else p?.barcode ?? '',
    ];
    _barcodeCtrls = [
      for (final b in initial) TextEditingController(text: b),
    ];
    _price = TextEditingController(
      text: p == null ? '' : '${p.price}',
    );
    _cost = TextEditingController(text: p == null ? '' : '${p.cost}');
    _stock = TextEditingController(text: p == null ? '0' : '${p.stockQty}');
    _minStock =
        TextEditingController(text: p == null ? '5' : '${p.minStock}');
    _categoryId = p?.categoryId;
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _barcodeCtrls) {
      c.dispose();
    }
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  void _addBarcodeRow([String value = '']) {
    setState(() => _barcodeCtrls.add(TextEditingController(text: value)));
  }

  void _removeBarcodeRow(int i) {
    if (_barcodeCtrls.length == 1) return; // يبقى سطر واحد على الأقل
    setState(() {
      _barcodeCtrls.removeAt(i).dispose();
    });
  }

  Future<void> _pickImage() async {
    final file = await ProductImageStore.pick();
    // الحفظ الفعلي يتم عند حفظ المنتج (تفادياً لملفات يتيمة)
    if (file != null && mounted) {
      setState(() {
        _newImage = file;
        _removeImage = false;
      });
    }
  }

  void _save() {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      setState(() => _formError = 'السعر غير صالح');
      return;
    }
    // كل باركود في سطر — الأول هو الرئيسي
    final codes = <String>[];
    for (final c in _barcodeCtrls) {
      final t = c.text.trim();
      if (t.isNotEmpty && !codes.contains(t)) codes.add(t);
    }
    if (codes.isEmpty) {
      setState(() => _formError = 'أدخل باركوداً واحداً على الأقل');
      return;
    }
    String? imagePath = widget.product?.imagePath;
    if (_removeImage) imagePath = null;
    context.read<InventoryBloc>().add(
          InventoryProductSaved(
            ProductDraft(
              id: widget.product?.id,
              name: _name.text.trim(),
              barcode: codes.first,
              barcodes: codes,
              price: price,
              cost: double.tryParse(_cost.text.trim()) ?? 0,
              stockQty: int.tryParse(_stock.text.trim()) ?? 0,
              minStock: int.tryParse(_minStock.text.trim()) ?? 0,
              categoryId: _categoryId,
              existingImagePath: imagePath,
              isActive: _isActive,
            ),
            newImage: _removeImage ? null : _newImage,
          ),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        context.select<InventoryBloc, List<InventoryCategory>>(
      (b) => b.state.categories,
    );
    final saving =
        context.select<InventoryBloc, bool>(
      (b) => b.state.status == InventoryStatus.saving,
    );
    final existingImage = widget.product?.imagePath;

    return AlertDialog(
      title: Text(isEdit ? 'تعديل المنتج' : 'منتج جديد'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الصورة
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: _preview(existingImage),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('اختيار صورة'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 48,
                            child: TextButton.icon(
                              onPressed: (_newImage == null &&
                                      (_removeImage ||
                                          existingImage == null))
                                  ? null
                                  : () => setState(() {
                                        _newImage = null;
                                        _removeImage = true;
                                      }),
                              icon: const Icon(Icons.hide_image_outlined),
                              label: const Text('إزالة الصورة'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'اسم المنتج *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 12),
                // الباركودات — كل باركود في سطر (الأول هو الرئيسي)
                const Text(
                  'الباركودات (كل باركود في سطر — الأول هو الرئيسي)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < _barcodeCtrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _barcodeCtrls[i],
                            decoration: InputDecoration(
                              labelText: i == 0
                                  ? 'الباركود * (رئيسي)'
                                  : 'باركود إضافي',
                              prefixIcon: const Icon(Icons.qr_code_2),
                              suffixIcon: i == 0
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close),
                                      tooltip: 'حذف الباركود',
                                      onPressed: () =>
                                          _removeBarcodeRow(i),
                                    ),
                            ),
                            validator: (v) =>
                                (i == 0 && (v == null || v.trim().isEmpty))
                                    ? 'أدخل الباركود'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _barcodeCtrls[i].text =
                                  DateTime.now().microsecondsSinceEpoch
                                      .toString();
                            }),
                            child: const Text('توليد'),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 48,
                  child: TextButton.icon(
                    onPressed: () => _addBarcodeRow(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة باركود آخر'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سعر البيع *',
                        ),
                        validator: (v) =>
                            double.tryParse((v ?? '').trim()) == null
                                ? 'سعر غير صالح'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سعر الشراء',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الكمية بالمخزون',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'حد التنبيه',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _categoryId,
                  decoration:
                      const InputDecoration(labelText: 'الفئة'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('بدون فئة'),
                    ),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _categoryId = v),
                ),
                SwitchListTile(
                  title: const Text('منتج نشط (يظهر في البيع)'),
                  value: _isActive,
                  onChanged: (v) =>
                      setState(() => _isActive = v),
                ),
                if (_formError != null)
                  Text(
                    _formError!,
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة المنتج'),
        ),
      ],
    );
  }

  Widget _preview(String? existingImage) {
    File? file;
    if (_newImage != null && !_removeImage) {
      file = _newImage;
    } else if (!_removeImage &&
        existingImage != null &&
        File(existingImage).existsSync()) {
      file = File(existingImage);
    }
    if (file != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(file, fit: BoxFit.cover),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.image_outlined, size: 40, color: Colors.grey),
    );
  }
}
