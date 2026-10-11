import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'app/shell.dart';
import 'app/theme.dart';
import 'core/database/app_database.dart';
import 'core/database/drift_repositories.dart';
import 'core/database/seed.dart';
import 'core/tts/arabic_tts_service.dart';
import 'features/inventory/bloc/inventory_bloc.dart';
import 'features/pos/bloc/pos_bloc.dart';
import 'features/settings/bloc/settings_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة النافذة — محمية: أي عطل هنا لا يمنع إقلاع التطبيق
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1440, 860),
        minimumSize: const Size(1280, 720),
        title: 'نظام نقطة البيع — مكتبة',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {
    // يعمل التطبيق بنافذة افتراضية
  }

  // قاعدة البيانات + بيانات أولية
  final db = AppDatabase();
  try {
    await ensureSeeded(db);
  } catch (_) {
    // يعمل التطبيق بقاعدة فارغة
  }

  // تهيئة النطق العربي (كسولة وآمنة: لا تمنع الإقلاع عند الفشل)
  try {
    await ArabicTtsService.instance.init();
  } catch (_) {
    // يعمل التطبيق بدون صوت
  }

  runApp(BookstorePosApp(db: db));
}

class BookstorePosApp extends StatelessWidget {
  final AppDatabase db;
  const BookstorePosApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PosBloc(
            repo: DriftCatalogRepository(db),
            checkoutRepo: DriftCheckoutRepository(db),
          ),
        ),
        BlocProvider(
          create: (_) => InventoryBloc(db: db),
        ),
        BlocProvider(
          create: (_) => SettingsCubit(db: db)..load(),
        ),
      ],
      child: MaterialApp(
        title: 'نقطة البيع — مكتبة',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // RTL كامل + عربي
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppShell(),
      ),
    );
  }
}
