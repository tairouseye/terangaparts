import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/parts_request.dart';
import '../../providers/auth_providers.dart';

/// Outils de l'ecran « Sourcer la piece » (v1.4.0) : reference lue par l'IA,
/// photo, message fournisseur en anglais, historique des sourcings.

/// Reference constructeur lue sur la photo par l'IA. Le formulaire de demande
/// l'ecrit dans les precisions : « Réf. lue sur la photo : 58101-2SA70 ».
String? oemRefFromNotes(String? notes) {
  if (notes == null) return null;
  final m = RegExp(r'Réf\. lue sur la photo\s*:\s*([A-Za-z0-9\-]+)')
      .firstMatch(notes);
  return m?.group(1);
}

/// Reference normalisee pour comparer (« 58101-2SA70 » == « 581012sa70 »).
String normalizeRef(String ref) =>
    ref.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Les photos sont enregistrees avec une URL signee valable 7 jours : on en
/// refait une fraiche a partir du chemin du fichier.
final freshPhotoUrlProvider =
    FutureProvider.family<String?, String>((ref, url) async {
  final m = RegExp(r'/object/sign/([^/]+)/([^?]+)').firstMatch(url);
  if (m == null) return url;
  final client = ref.watch(supabaseClientProvider);
  try {
    return await client.storage
        .from(m.group(1)!)
        .createSignedUrl(Uri.decodeComponent(m.group(2)!), 60 * 60);
  } catch (_) {
    return url;
  }
});

/// Message pour un fournisseur coreen (ils repondent en anglais).
String supplierMessageEn(PartsRequest r, {String? reference}) {
  final ref = reference?.trim() ?? '';
  return [
    'Hello, we are looking for this part:',
    'Part: ${r.partName}',
    if (ref.isNotEmpty) 'OEM part number: $ref',
    'Vehicle: ${r.vehicleLabel}',
    if (r.vehicleEngine != null && r.vehicleEngine!.isNotEmpty)
      'Engine: ${r.vehicleEngine}',
    if (r.vehicleVin != null && r.vehicleVin!.isNotEmpty)
      'VIN: ${r.vehicleVin}',
    'Quantity: 1',
    '',
    'Could you send the exact part number, price, weight and lead time? '
        'Thank you.',
  ].join('\n');
}

/// Un sourcing deja fait (proposition fournisseur + demande d'origine).
class PastSourcing {
  final String? partRef;
  final String partName;
  final String vehicle;
  final String? source;
  final num? buyPriceKrw;
  final num? weightKg;
  final String? dimensions;
  final int? leadTimeDays;
  final String? sourceUrl;
  final bool available;
  final DateTime? createdAt;
  final bool sameRef; // meme reference (sinon : meme piece, meme modele)

  const PastSourcing({
    required this.partRef,
    required this.partName,
    required this.vehicle,
    required this.source,
    required this.buyPriceKrw,
    required this.weightKg,
    required this.dimensions,
    required this.leadTimeDays,
    required this.sourceUrl,
    required this.available,
    required this.createdAt,
    required this.sameRef,
  });
}

/// Cle de recherche de l'historique.
class HistoryKey {
  final String requestId;
  final String? reference;
  final String partName;
  final String? model;
  const HistoryKey(this.requestId, this.reference, this.partName, this.model);

  @override
  bool operator ==(Object other) =>
      other is HistoryKey &&
      other.requestId == requestId &&
      other.reference == reference &&
      other.partName == partName &&
      other.model == model;

  @override
  int get hashCode => Object.hash(requestId, reference, partName, model);
}

/// Sourcings precedents : meme reference, ou meme piece sur le meme modele.
/// Les plus pertinents (meme reference) d'abord, puis du plus recent.
final sourcingHistoryProvider =
    FutureProvider.family<List<PastSourcing>, HistoryKey>((ref, key) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('suppliers_quotes')
      .select('part_ref, source, buy_price_krw, weight_kg, dimensions, '
          'lead_time_days, source_url, available, created_at, request_id, '
          'parts_requests!inner(part_name, vehicle_brand, vehicle_model, '
          'vehicle_year)')
      .neq('request_id', key.requestId)
      .order('created_at', ascending: false)
      .limit(300);
  return pastSourcingsFrom(rows as List, key);
});

/// Filtre / trie les lignes (separe pour etre teste sans Supabase).
List<PastSourcing> pastSourcingsFrom(List rows, HistoryKey key) {
  final wantRef =
      key.reference == null ? '' : normalizeRef(key.reference!);
  final wantPart = key.partName.trim().toLowerCase();
  final wantModel = (key.model ?? '').trim().toLowerCase();
  final out = <PastSourcing>[];
  for (final raw in rows) {
    final j = raw as Map<String, dynamic>;
    final req = (j['parts_requests'] ?? const {}) as Map<String, dynamic>;
    final ref = j['part_ref'] as String?;
    final sameRef =
        wantRef.isNotEmpty && ref != null && normalizeRef(ref) == wantRef;
    final samePart = wantPart.isNotEmpty &&
        wantModel.isNotEmpty &&
        ((req['part_name'] ?? '') as String).trim().toLowerCase() ==
            wantPart &&
        ((req['vehicle_model'] ?? '') as String).trim().toLowerCase() ==
            wantModel;
    if (!sameRef && !samePart) continue;
    final vehicle = PartsRequest(
      clientId: '',
      partName: '',
      vehicleBrand: req['vehicle_brand'] as String?,
      vehicleModel: req['vehicle_model'] as String?,
      vehicleYear: req['vehicle_year'] as int?,
    ).vehicleLabel;
    out.add(PastSourcing(
      partRef: ref,
      partName: (req['part_name'] ?? '') as String,
      vehicle: vehicle,
      source: j['source'] as String?,
      buyPriceKrw: j['buy_price_krw'] as num?,
      weightKg: j['weight_kg'] as num?,
      dimensions: j['dimensions'] as String?,
      leadTimeDays: j['lead_time_days'] as int?,
      sourceUrl: j['source_url'] as String?,
      available: (j['available'] ?? true) as bool,
      createdAt: j['created_at'] == null
          ? null
          : DateTime.tryParse(j['created_at'] as String),
      sameRef: sameRef,
    ));
  }
  out.sort((a, b) {
    if (a.sameRef != b.sameRef) return a.sameRef ? -1 : 1;
    return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
  });
  return out.take(5).toList();
}
