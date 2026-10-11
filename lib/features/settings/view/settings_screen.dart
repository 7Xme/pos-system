import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/images/product_image_store.dart';
import '../../../core/tts/arabic_tts_service.dart';
import '../../inventory/bloc/inventory_bloc.dart';
import '../bloc/settings_cubit.dart';

/// شاشة الإعدادات: بيانات المتجر + سلوك البيع + إدارة أزرار الاختصار
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _shop;
  late final TextEditingController _cashier;
  late final TextEditingController _currency;
  late final TextEditingController _phone;
  File? _newLogo;
  bool _removeLogo = false;
  bool _testingSound = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsCubit>().state;
    _shop = TextEditingController(text: s.shopName);
    _cashier = TextEditingController(text: s.cashier);
    _currency = TextEditingController(text: s.currency);
    _phone = TextEditingController(text: s.phone);
  }

  @override
  void dispose() {
    _shop.dispose();
    _cashier.dispose();
    _currency.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ProductImageStore.pick();
    if (file != null && mounted) {
      setState(() {
        _newLogo = file;
        _removeLogo = false;
      });
    }
  }

  Future<void> _saveStore() async {
    final shop = _shop.text.trim();
    final cashier = _cashier.text.trim();
    final currency = _currency.text.trim();
    final phone = _phone.text.trim();
    if (shop.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المتجر')),
      );
      return;
    }
    // حفظ الشعار الجديد (إن وُجد) — وإلا الإبقاء على الحالي أو إزالته
    String? Function()? logoPath;
    if (_removeLogo) {
      logoPath = () => null;
    } else if (_newLogo != null) {
      try {
        final saved = await ProductImageStore.save(_newLogo!);
        logoPath = () => saved;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر حفظ الشعار')),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await context.read<SettingsCubit>().update(
          shopName: shop,
          cashier: cashier.isEmpty ? 'كاشير' : cashier,
          currency: currency.isEmpty ? 'درهم' : currency,
          phone: phone,
          logoPath: logoPath,
        );
    if (!mounted) return;
    setState(() {
      _newLogo = null;
      _removeLogo = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ بيانات المتجر')),
    );
  }

  Future<void> _testSound() async {
    setState(() => _testingSound = true);
    final source = context.read<SettingsCubit>().state.ttsSource;
    TtsDiagnosis diag;
    try {
      diag = await ArabicTtsService.instance.diagnose(source: source);
    } catch (e) {
      diag = (
        comOk: false,
        voiceCreated: false,
        speakOk: false,
        speakHr: 0,
        onlineOk: false,
        sourceUsed: source.name,
        voices: const [],
        arabicCount: 0,
        error: 'فشل الفحص: $e',
      );
    }
    if (!mounted) return;
    setState(() => _testingSound = false);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نتيجة اختبار الصوت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _diagRow('نظام COM', diag.comOk),
              _diagRow('إنشاء صوت SAPI', diag.voiceCreated),
              _diagRow('الإنترنت (صوت أونلاين)', diag.onlineOk),
              _diagRow(
                'إرسال أمر النطق (${_sourceLabel(diag.sourceUsed)})',
                diag.speakOk,
                detail: diag.speakOk
                    ? null
                    : 'كود: 0x${diag.speakHr.toUnsigned(32).toRadixString(16)}',
              ),
              _diagRow(
                'صوت عربي مثبت (${diag.arabicCount})',
                diag.arabicCount > 0,
              ),
              if (diag.voices.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'الأصوات المثبتة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final v in diag.voices)
                  Text('• ${v.name}  [${v.lang}]'),
              ] else
                const Text('لا توجد أصوات نطق مثبتة إطلاقاً.'),
              if (diag.arabicCount == 0) ...[
                const SizedBox(height: 8),
                const Text(
                  'لتثبيت صوت عربي: إعدادات ويندوز ← الوقت واللغة ← اللغة ← أضف العربية ← خياراتها ← حمّل حزمة الصوت (Speech). ثم أعد الاختبار.',
                ),
              ],
              if (diag.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  diag.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              if (diag.error == null && diag.speakOk) ...[
                const SizedBox(height: 8),
                const Text('إذا لم تسمع شيئاً فراجع مستوى السماعات.'),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Widget _diagRow(String label, bool ok, {String? detail}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$label${detail == null ? '' : ' — $detail'}'),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String name) {
    switch (name) {
      case 'sapi':
        return 'ويندوز';
      case 'online':
        return 'أونلاين';
      default:
        return 'تلقائي';
    }
  }

  bool _clearLogoVisible() {
    if (_newLogo != null && !_removeLogo) return true;
    final current = context.read<SettingsCubit>().state.logoPath;
    return !_removeLogo && current != null && File(current).existsSync();
  }

  Widget _logoPreview() {
    File? file;
    if (_newLogo != null && !_removeLogo) {
      file = _newLogo;
    } else if (!_removeLogo) {
      final current = context.read<SettingsCubit>().state.logoPath;
      if (current != null && File(current).existsSync()) {
        file = File(current);
      }
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
      child: const Icon(
        Icons.store_outlined,
        size: 40,
        color: Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.select<SettingsCubit, String>(
      (c) => c.state.currency,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // بيانات المتجر
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'بيانات المتجر (تظهر في الفاتورة)',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _shop,
                          decoration: const InputDecoration(
                            labelText: 'اسم المتجر',
                            prefixIcon: Icon(Icons.store_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cashier,
                          decoration: const InputDecoration(
                            labelText: 'اسم الكاشير',
                            prefixIcon:
                                Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _currency,
                          decoration: const InputDecoration(
                            labelText: 'العملة (مثال: درهم)',
                            prefixIcon:
                                Icon(Icons.payments_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'هاتف المتجر (يظهر في الفاتورة)',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // شعار المتجر
                        Row(
                          children: [
                            SizedBox(
                              width: 96,
                              height: 96,
                              child: _logoPreview(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      onPressed: _pickLogo,
                                      icon: const Icon(
                                        Icons.image_outlined,
                                      ),
                                      label:
                                          const Text('اختيار شعار'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 48,
                                    child: TextButton.icon(
                                      onPressed: _clearLogoVisible()
                                          ? () => setState(() {
                                                _newLogo = null;
                                                _removeLogo = true;
                                              })
                                          : null,
                                      icon: const Icon(
                                        Icons.hide_image_outlined,
                                      ),
                                      label:
                                          const Text('إزالة الشعار'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _saveStore,
                            child: const Text('حفظ بيانات المتجر'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // سلوك البيع
                BlocBuilder<SettingsCubit, ShopSettings>(
                  builder: (context, s) {
                    final cubit = context.read<SettingsCubit>();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'سلوك البيع',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SwitchListTile(
                              title: const Text(
                                'نطق المجموع صوتياً بعد البيع',
                              ),
                              subtitle: const Text(
                                'يحتاج سماعات وصوت عربي في الويندوز',
                              ),
                              value: s.soundEnabled,
                              onChanged: (v) =>
                                  cubit.update(soundEnabled: v),
                            ),
                            SwitchListTile(
                              title: const Text(
                                'طباعة الفاتورة تلقائياً بعد البيع',
                              ),
                              subtitle: const Text(
                                'إلغاؤها يتيح مراجعة السلة قبل الطباعة',
                              ),
                              value: s.autoPrint,
                              onChanged: (v) =>
                                  cubit.update(autoPrint: v),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // اختبار الصوت
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'اختبار الصوت العربي',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'يفحص نظام الصوت في الويندوز ويعرض الأصوات المثبتة وسبب أي عطل.',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed:
                                _testingSound ? null : _testSound,
                            icon: _testingSound
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Icon(Icons.volume_up_outlined),
                            label: const Text(
                              'تشغيل اختبار الصوت',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // أزرار الاختصار
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'أزرار الاختصار (شاشة البيع)',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ثبت المنتجات الأكثر مبيعاً بزر النجمة ★ في شاشة المنتجات لتظهر كأزرار سريعة أعلى شبكة البيع.',
                        ),
                        const SizedBox(height: 12),
                        BlocBuilder<InventoryBloc, InventoryState>(
                          builder: (context, inv) {
                            final favs = inv.favoriteProducts;
                            if (favs.isEmpty) {
                              return const Text(
                                'لا توجد أزرار اختصار بعد.',
                                style: TextStyle(color: Colors.grey),
                              );
                            }
                            return Column(
                              children: [
                                for (final f in favs)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                    ),
                                    title: Text(f.name),
                                    subtitle: Text(
                                      '${f.price.toStringAsFixed(2)} $currency',
                                    ),
                                    trailing: IconButton.outlined(
                                      onPressed: () => context
                                          .read<InventoryBloc>()
                                          .add(
                                            InventoryFavoriteToggled(
                                              f.id,
                                              false,
                                            ),
                                          ),
                                      icon: const Icon(
                                        Icons.star_outline,
                                      ),
                                      tooltip: 'إزالة من الاختصارات',
                                    ),
                                  ),
                              ],
                            );
                          },
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
