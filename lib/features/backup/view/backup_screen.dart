import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/backup/backup_service.dart';
import '../../inventory/bloc/inventory_bloc.dart';

/// شاشة النسخ الاحتياطي: تصدير ZIP (قاعدة البيانات + الصور) واستيراده.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  int _statsTick = 0;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.exportBackup(
        context.read<InventoryBloc>().db,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null ? 'تم إلغاء التصدير' : 'تم حفظ النسخة في:\n$path',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر التصدير: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statsTick++;
        });
      }
    }
  }

  Future<void> _import() async {
    final db = context.read<InventoryBloc>().db;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text(
          'سيتم استبدال كل البيانات الحالية (المنتجات والفواتير والصور) '
          'بمحتوى ملف ZIP المختار. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اختيار الملف'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final done = await BackupService.importBackup(db);
      if (!mounted) return;
      if (!done) return; // ألغى المستخدم اختيار الملف
      final restart = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('تم الاستيراد بنجاح'),
          content: const Text('يجب إعادة تشغيل التطبيق لتطبيق البيانات الجديدة.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إعادة التشغيل الآن'),
            ),
          ],
        ),
      );
      if (restart == true) await BackupService.relaunchApp();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الاستيراد: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statsTick++;
        });
      }
    }
  }

  String _statsText(({bool hasDb, int dbKb, int imageCount})? s) {
    if (s == null) return 'جاري قراءة معلومات البيانات...';
    if (!s.hasDb) return 'لا توجد بيانات محفوظة بعد';
    return 'قاعدة البيانات: ${s.dbKb} KB - الصور: ${s.imageCount}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder(
                  key: ValueKey(_statsTick),
                  future: BackupService.stats(),
                  builder: (ctx, snap) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storage_outlined,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _statsText(snap.data),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'تصدير نسخة احتياطية',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'يحفظ ملف ZIP واحد يحتوي قاعدة البيانات (المنتجات والفئات والفواتير) ومجلد صور المنتجات. انسخه على فلاشة أو جهاز آخر للأمان.',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _export,
                            icon: _busy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Icon(Icons.upload_outlined, size: 26),
                            label: const Text(
                              'تصدير ZIP الآن',
                              style: TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'استيراد نسخة احتياطية',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'اختر ملف ZIP سبق تصديره: يفك التطبيق ضغطه ويستبدل قاعدة البيانات الحالية ومجلد الصور، ثم يعيد التشغيل.',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _import,
                            icon: const Icon(
                              Icons.download_outlined,
                              size: 26,
                            ),
                            label: const Text(
                              'استيراد من ملف ZIP',
                              style: TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
