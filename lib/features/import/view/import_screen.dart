import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/images/product_image_store.dart';
import '../../inventory/bloc/inventory_bloc.dart';
import '../../pos/bloc/pos_bloc.dart';
import '../import_service.dart';

/// استيراد كتالوج المنتجات من مجلد البيانات (data) الذي يوفّره المطوّر —
/// يجلب الأسماء والأسعار والباركودات والصور دفعة واحدة.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;
  bool _copyImages = false;
  bool _cancelRequested = false;
  String? _selectedDir;
  int? _currentCount;
  int _statsTick = 0;

  ImportProgress? _progress;
  ImportResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final db = context.read<InventoryBloc>().db;
    final n = await ProductImportService.currentProductCount(db);
    if (mounted) setState(() => _currentCount = n);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد data الذي توصّلت به من المطوّر',
    );
    if (dir == null || !mounted) return;
    final found = ProductImportService.findDatabaseIn(dir);
    setState(() {
      _selectedDir = found == null ? null : dir;
      _error = found == null
          ? 'لم يُعثر على ${ProductImportService.dbFileName} داخل المجلد المختار.\n'
              'اختر مجلد «data» الذي توصّلت به من المطوّر.'
          : null;
      _result = null;
    });
  }

  Future<void> _runImport() async {
    final dir = _selectedDir;
    if (dir == null) return;
    final sourcePath = ProductImportService.findDatabaseIn(dir);
    if (sourcePath == null) return;

    final inv = context.read<InventoryBloc>();
    final pos = context.read<PosBloc>();

    setState(() {
      _busy = true;
      _cancelRequested = false;
      _error = null;
      _result = null;
      _progress = null;
    });

    try {
      final imagesDest = await _imagesDestination();
      final result = await ProductImportService.importFrom(
        target: inv.db,
        sourcePath: sourcePath,
        copyImages: _copyImages,
        imagesDestination: imagesDest,
        isCancelled: () => _cancelRequested,
        onProgress: (pr) {
          if (mounted) setState(() => _progress = pr);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
      // تحديث الواجهات
      ProductImageStore.clearCache();
      inv.add(InventoryStarted());
      pos.add(PosCatalogRefreshed());
      _statsTick++;
      await _loadCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<String> _imagesDestination() async {
    // نفس مجلد صور التطبيق الذي يستعمله شاشة المنتجات
    // (مجلد data المحمول أو مسار دعم التطبيق).
    return (await ProductImageStore.imagesDirectory()).path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد المنتجات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCard(),
                const SizedBox(height: 16),
                _sourceCard(),
                const SizedBox(height: 16),
                if (_busy || _progress != null) _progressCard(),
                if (_error != null) _errorCard(_error!),
                if (_result != null) _resultCard(_result!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final count = _currentCount;
    return Card(
      key: ValueKey('summary-$_statsTick'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == null
                    ? 'جاري قراءة عدد المنتجات...'
                    : 'المنتجات الحالية في التطبيق: $count',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'مصدر البيانات',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر مجلد «data» الذي توصّلت به من المطوّر '
              '(مثلاً على سطح المكتب أو ذاكرة USB). يحتوي على '
              'bookstore_pos.sqlite (الأسماء والأسعار والباركودات) '
              'ومجلد product_images (الصور).',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedDir ?? 'لم يتم اختيار مجلد بعد',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _copyImages,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _copyImages = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('نسخ الصور إلى مجلد التطبيق'),
              subtitle: const Text(
                'بدون تحديد، يشير التطبيق إلى الصور داخل مجلد البيانات مباشرة '
                '(أسرع ولا يضاعف المساحة). عند النسخ تبقى الصور حتى لو حُذف المجلد.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFolder,
                      icon: const Icon(Icons.folder_open, size: 26),
                      label: const Text('اختيار مجلد البيانات',
                          style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed:
                          (_busy || _selectedDir == null) ? null : _runImport,
                      icon: _busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(Icons.download_outlined, size: 26),
                      label: const Text('استيراد الآن',
                          style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _cancelRequested = true),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('إلغاء'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _progressCard() {
    final pr = _progress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pr == null
                  ? 'جاري التحضير...'
                  : 'جاري الاستيراد: ${pr.processed} / ${pr.total}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: pr?.fraction),
            const SizedBox(height: 8),
            if (pr != null)
              Text('تمت إضافة ${pr.inserted} • تم تخطي ${pr.skipped}'),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(ImportResult r) {
    if (r.cancelled) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('أُلغي الاستيراد — ما تم إدخاله محفوظ.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 32),
                SizedBox(width: 8),
                Text('تم الاستيراد',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _row('منتجات جديدة', r.productsInserted),
            _row('منتجات مُتخطاة (موجودة مسبقاً)', r.productsSkipped),
            _row('فئات جديدة', r.categoriesCreated),
            if (r.imagesCopied > 0) _row('صور منسوخة', r.imagesCopied),
            if (r.imagesMissing > 0)
              _row('صور غير موجودة', r.imagesMissing),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text('$value',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
