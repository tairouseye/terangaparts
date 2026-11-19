import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/open_tab.dart';
import '../../models/parts_request.dart';
import '../../providers/admin_counts_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/quote_providers.dart';
import 'build_quote_screen.dart';
import 'orders_screen.dart';
import 'source_part_screen.dart';

/// Une ligne « à traiter » de l'accueil admin.
class AdminTodoItem {
  final String kind; // 'sourcer' | 'chiffrer' | 'acompte'
  final String title;
  final String subtitle;
  final String? clientName;
  final String? clientWhatsapp;
  final DateTime? createdAt;
  final PartsRequest? request;

  const AdminTodoItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.clientName,
    this.clientWhatsapp,
    this.createdAt,
    this.request,
  });
}

/// Ce qui attend l'admin, du plus ancien au plus recent (premier arrive,
/// premier servi) : demandes a sourcer, pieces a chiffrer, acomptes a
/// verifier. Une seule requete par type ; le nom et le WhatsApp du client
/// viennent de profiles (lisible par l'admin).
final adminTodoProvider =
    FutureProvider.autoDispose<List<AdminTodoItem>>((ref) async {
  final c = ref.watch(supabaseClientProvider);

  final requests = await c
      .from('parts_requests')
      .select('*, profiles(full_name, whatsapp)')
      .inFilter('status', ['nouvelle_demande', 'recherche_coree', 'piece_trouvee'])
      .order('created_at', ascending: true);

  final orders = await c
      .from('orders')
      .select('id, created_at, profiles(full_name, whatsapp)')
      .eq('status', 'acompte_paye')
      .order('created_at', ascending: true);

  final items = <AdminTodoItem>[];
  for (final row in (requests as List).cast<Map<String, dynamic>>()) {
    final r = PartsRequest.fromJson(row);
    final p = row['profiles'] as Map<String, dynamic>?;
    final toQuote = row['status'] == 'piece_trouvee';
    items.add(AdminTodoItem(
      kind: toQuote ? 'chiffrer' : 'sourcer',
      title: r.partName,
      subtitle: r.vehicleLabel,
      clientName: (p?['full_name'] as String?)?.trim(),
      clientWhatsapp: (p?['whatsapp'] as String?)?.trim(),
      createdAt: r.createdAt,
      request: r,
    ));
  }
  for (final row in (orders as List).cast<Map<String, dynamic>>()) {
    final p = row['profiles'] as Map<String, dynamic>?;
    items.add(AdminTodoItem(
      kind: 'acompte',
      title: 'Acompte 70 % à vérifier',
      subtitle: 'Confirmez la réception avant de commander la pièce',
      clientName: (p?['full_name'] as String?)?.trim(),
      clientWhatsapp: (p?['whatsapp'] as String?)?.trim(),
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    ));
  }
  return items;
});

/// Bloc « À traiter » de l'accueil admin : chaque ligne dit quoi faire et
/// mene directement a l'ecran qui le fait, avec WhatsApp du client a cote.
class AdminTodoSection extends ConsumerWidget {
  const AdminTodoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTodoProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => const Text('« À traiter » indisponible pour le moment.',
          style: TextStyle(color: AppColors.gris)),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        const maxShown = 6;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('À traiter',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ambre,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${items.length}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            for (final it in items.take(maxShown)) _TodoCard(item: it),
            if (items.length > maxShown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '+ ${items.length - maxShown} autre(s) dans les rubriques '
                    'ci-dessous.',
                    style: const TextStyle(fontSize: 12, color: AppColors.gris)),
              ),
          ],
        );
      },
    );
  }
}

class _TodoCard extends ConsumerWidget {
  final AdminTodoItem item;
  const _TodoCard({required this.item});

  (String, IconData, Color) get _badge => switch (item.kind) {
        'chiffrer' => ('À chiffrer', Icons.calculate, AppColors.vert),
        'acompte' => ('Paiement', Icons.payments, AppColors.ambre),
        _ => ('À sourcer', Icons.search, AppColors.primary),
      };

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final Widget page = switch (item.kind) {
      'chiffrer' => BuildQuoteScreen(request: item.request!),
      'acompte' => const OrdersScreen(),
      _ => SourcePartScreen(request: item.request!),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    ref.invalidate(adminTodoProvider);
    ref.invalidate(adminCountsProvider);
    ref.invalidate(newPartsRequestsProvider);
    ref.invalidate(requestsToQuoteProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, icon, color) = _badge;
    final who = item.clientName?.isNotEmpty == true ? item.clientName! : 'Client';
    final wa = item.clientWhatsapp ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              const Spacer(),
              Text(Formatters.date(item.createdAt),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.gris)),
            ]),
            const SizedBox(height: 4),
            Text(item.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${item.subtitle} · $who',
                style: const TextStyle(fontSize: 12.5, color: AppColors.gris)),
            const SizedBox(height: 6),
            Row(children: [
              if (wa.replaceAll(RegExp(r'[^0-9]'), '').length >= 9)
                TextButton.icon(
                  onPressed: () => openInNewTab(AppInfo.whatsappTo(
                    _e164(wa),
                    'Bonjour $who, ici Teranga Parts au sujet de votre '
                    'demande : ${item.title}.',
                  )),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp'),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _open(context, ref),
                child: const Text('Traiter'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Numero local senegalais (9 chiffres) -> indicatif 221 ajoute.
  static String _e164(String raw) {
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 9) return '221$d';
    if (d.startsWith('00')) return d.substring(2);
    return d;
  }
}
