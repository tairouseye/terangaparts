import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/update_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Garde-fou : sans projet Supabase Teranga Parts configure, on n'ouvre
  // aucune connexion (evite d'ecrire par erreur dans une autre base).
  if (!SupabaseConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const ProviderScope(child: TerangaPartsApp()));
}

class TerangaPartsApp extends ConsumerWidget {
  const TerangaPartsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Teranga Parts — Pièces détachées coréennes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      // « Nouvelle version disponible » sur tous les ecrans.
      builder: (context, child) =>
          UpdateWatcher(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Teranga Parts : projet Supabase non configuré.\n'
                'Renseignez SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
