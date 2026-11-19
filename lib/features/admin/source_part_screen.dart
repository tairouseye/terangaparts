import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../core/config/parts_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/open_tab.dart';
import '../../models/parts_request.dart';
import '../../models/supplier_quote.dart';
import '../../providers/auth_providers.dart';
import '../../providers/partner_providers.dart';
import '../../providers/quote_providers.dart';
import 'build_quote_screen.dart';
import 'sourcing_helpers.dart';

/// Admin : sourcing d'une piece (v1.4.0).
/// 1. Trouver la reference (lue par l'IA sur la photo, catalogue par VIN).
/// 2. Comparer les fournisseurs (recherche pre-remplie, message en anglais),
///    avec l'historique des sourcings deja faits.
/// 3. Saisir la proposition retenue. A la validation, la demande passe a
///    'piece_trouvee' (trigger) et on ouvre le chiffrage du devis.
class SourcePartScreen extends ConsumerStatefulWidget {
  final PartsRequest request;
  const SourcePartScreen({super.key, required this.request});

  @override
  ConsumerState<SourcePartScreen> createState() => _SourcePartScreenState();
}

class _SourcePartScreenState extends ConsumerState<SourcePartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _partRef = TextEditingController();
  final _priceKrw = TextEditingController();
  final _weight = TextEditingController();
  final _dimensions = TextEditingController();
  final _leadTime = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _usdRate =
      TextEditingController(text: PartsConfig.defaultUsdToKrw.toString());
  PartsSupplier _supplier = PartsConfig.suppliers.first;
  bool _available = true;
  bool _saving = false;
  String? _error;

  /// Reference lue par l'IA sur la photo du client (si elle existe).
  late final String? _aiRef = oemRefFromNotes(widget.request.notes);

  @override
  void initState() {
    super.initState();
    if (_aiRef != null) _partRef.text = _aiRef;
    // Rafraichit les liens et l'historique quand la reference change.
    _partRef.addListener(_onRefChanged);
  }

  void _onRefChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _partRef.removeListener(_onRefChanged);
    for (final c in [
      _partRef,
      _priceKrw,
      _weight,
      _dimensions,
      _leadTime,
      _sourceUrl,
      _usdRate
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _supplierMessage() =>
      supplierMessageEn(widget.request, reference: _partRef.text);

  void _open(String url) => openInNewTab(url);

  bool get _isUsd => _supplier.currency == 'USD';

  /// Prix saisi converti en KRW (le devis serveur est calcule depuis le KRW).
  num? _priceInKrw() {
    final price = num.tryParse(_priceKrw.text.trim().replaceAll(',', '.'));
    if (price == null) return null;
    if (!_isUsd) return price;
    final rate = num.tryParse(_usdRate.text.trim().replaceAll(',', '.'));
    if (rate == null || rate <= 0) return null;
    return (price * rate).round();
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: _supplierMessage()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Message (en anglais) copié : collez-le dans WhatsApp '
            'ou un email.')));
  }

  /// Reprend les valeurs d'un sourcing precedent dans le formulaire.
  void _reuse(PastSourcing p) {
    setState(() {
      final sup = PartsConfig.suppliers.where((s) => s.id == p.source);
      if (sup.isNotEmpty) _supplier = sup.first;
      if (p.partRef != null) _partRef.text = p.partRef!;
      _available = p.available;
      // Le prix enregistre est en KRW : repris tel quel, ou converti en USD
      // au taux du formulaire si le fournisseur affiche en USD.
      if (p.buyPriceKrw != null) {
        if (_isUsd) {
          final rate =
              num.tryParse(_usdRate.text.trim().replaceAll(',', '.')) ??
                  PartsConfig.defaultUsdToKrw;
          _priceKrw.text = (p.buyPriceKrw! / rate).toStringAsFixed(2);
        } else {
          _priceKrw.text = p.buyPriceKrw!.round().toString();
        }
      }
      if (p.weightKg != null) _weight.text = p.weightKg.toString();
      if (p.dimensions != null) _dimensions.text = p.dimensions!;
      if (p.leadTimeDays != null) _leadTime.text = p.leadTimeDays.toString();
      if (p.sourceUrl != null) _sourceUrl.text = p.sourceUrl!;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Valeurs reprises : vérifiez le prix du jour avant '
            "d'enregistrer.")));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(authServiceProvider).currentUser?.id;
    if (uid == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quote = SupplierQuote(
        requestId: widget.request.id!,
        partnerId: uid, // l'admin joue le role de sourcing
        partRef: _partRef.text.trim().isEmpty ? null : _partRef.text.trim(),
        available: _available,
        buyPriceKrw: _priceInKrw(),
        weightKg: num.tryParse(_weight.text.trim().replaceAll(',', '.')),
        dimensions:
            _dimensions.text.trim().isEmpty ? null : _dimensions.text.trim(),
        leadTimeDays: int.tryParse(_leadTime.text.trim()),
        source: _supplier.id,
        sourceUrl:
            _sourceUrl.text.trim().isEmpty ? null : _sourceUrl.text.trim(),
      );
      await ref.read(supplierQuoteServiceProvider).submit(quote);
      ref.invalidate(newPartsRequestsProvider);
      ref.invalidate(requestsToQuoteProvider);
      ref.invalidate(quotesForRequestProvider(widget.request.id!));
      if (mounted) {
        // Enchaine sur le chiffrage du devis.
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => BuildQuoteScreen(request: widget.request),
        ));
      }
    } catch (e) {
      setState(() => _error = 'Enregistrement impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final refText = _partRef.text.trim();
    final hasVin = r.vehicleVin != null && r.vehicleVin!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Sourcer la pièce')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Récap de la demande
              Card(
                color: AppColors.grisClair,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.partName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      _info('Véhicule', r.vehicleLabel),
                      _info('Motorisation', r.vehicleEngine),
                      _info('VIN', r.vehicleVin),
                      _info('Reçue le', Formatters.date(r.createdAt)),
                      if (r.notes != null && r.notes!.isNotEmpty)
                        _info('Détails', r.notes),
                      if (r.partPhotoUrl != null)
                        _PartPhoto(url: r.partPhotoUrl!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------------------------------------------------------
              _step('1. Trouver la référence'),
              if (_aiRef != null)
                _hint(Icons.auto_awesome,
                    'Référence lue sur la photo du client : $_aiRef '
                    '(déjà remplie, à vérifier).'),
              _field(_partRef, 'Référence constructeur (OEM)'),
              if (hasVin)
                OutlinedButton.icon(
                  onPressed: () =>
                      _open(PartsConfig.vinCatalogUrl(r.vehicleVin!)),
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: const Text('Catalogue constructeur par VIN'),
                )
              else
                _hint(Icons.info_outline,
                    'Pas de VIN : demandez au client une photo de sa carte '
                    'grise pour trouver la référence exacte.'),
              const Divider(height: 32),

              // ---------------------------------------------------------
              _step('2. Comparer les fournisseurs'),
              Text(
                  refText.isEmpty
                      ? 'Saisissez la référence pour ouvrir chaque site '
                          'directement sur la recherche.'
                      : 'Chaque bouton cherche « $refText ». Les messages '
                          'aux fournisseurs sont en anglais.',
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.gris)),
              const SizedBox(height: 8),
              for (final sup in PartsConfig.suppliers) _supplierTile(sup),
              _History(
                historyKey: HistoryKey(
                    r.id ?? '', refText, r.partName, r.vehicleModel),
                onReuse: _reuse,
              ),
              const Divider(height: 32),

              // ---------------------------------------------------------
              _step('3. Saisir la proposition'),
              DropdownButtonFormField<PartsSupplier>(
                key: ValueKey(_supplier.id),
                initialValue: _supplier,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Fournisseur retenu'),
                items: [
                  for (final sup in PartsConfig.suppliers)
                    DropdownMenuItem(value: sup, child: Text(sup.name)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _supplier = v);
                },
              ),
              const SizedBox(height: 6),
              Text(_supplier.note,
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.gris)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pièce disponible'),
                value: _available,
                activeThumbColor: AppColors.vert,
                onChanged: (v) => setState(() => _available = v),
              ),
              _field(_priceKrw, 'Prix d\'achat (${_supplier.currency}) *',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  required: true),
              if (_isUsd)
                _field(_usdRate, 'Taux USD → KRW *',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                    required: true),
              _field(_weight, 'Poids (kg)',
                  keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _field(_dimensions, 'Dimensions (L x l x h cm)'),
              _field(_leadTime, 'Délai fournisseur (jours)',
                  keyboard: TextInputType.number),
              _field(_sourceUrl, 'Lien chez le fournisseur (interne)',
                  keyboard: TextInputType.url),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.calculate),
                label: const Text('Enregistrer et chiffrer le devis'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Une carte par fournisseur : chercher, ecrire, retenir.
  Widget _supplierTile(PartsSupplier sup) {
    final selected = sup.id == _supplier.id;
    final refText = _partRef.text.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: selected ? AppColors.vert : Colors.black12,
            width: selected ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${sup.name}  ·  ${sup.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text('Retenu',
                      style: TextStyle(
                          color: AppColors.vert,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                )
              else
                TextButton(
                  onPressed: () => setState(() => _supplier = sup),
                  child: const Text('Retenir'),
                ),
            ]),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: () => _open(sup.urlFor(refText)),
                icon: const Icon(Icons.travel_explore, size: 16),
                label: Text(refText.isEmpty
                    ? 'Ouvrir le site'
                    : sup.hasSearch
                        ? 'Chercher'
                        : 'Chercher (Google)'),
              ),
              if (sup.whatsapp != null)
                OutlinedButton.icon(
                  onPressed: () => _open(
                      AppInfo.whatsappTo(sup.whatsapp!, _supplierMessage())),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('WhatsApp'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _copyMessage,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copier le message'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _step(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _hint(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.vert),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );

  Widget _info(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.gris))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null
            : null,
      ),
    );
  }
}

/// Photo de la piece envoyee par le client (lien rafraichi, clic = plein
/// ecran dans un nouvel onglet).
class _PartPhoto extends ConsumerWidget {
  final String url;
  const _PartPhoto({required this.url});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(freshPhotoUrlProvider(url)).value;
    if (u == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => openInNewTab(u),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(u,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Text('Photo jointe (cliquez pour l\'ouvrir)')),
        ),
      ),
    );
  }
}

/// « Déjà sourcé » : meme reference, ou meme piece sur le meme modele.
class _History extends ConsumerWidget {
  final HistoryKey historyKey;
  final void Function(PastSourcing) onReuse;
  const _History({required this.historyKey, required this.onReuse});

  static String _supplierName(String? id) {
    for (final s in PartsConfig.suppliers) {
      if (s.id == id) return s.name;
    }
    return id ?? 'Fournisseur';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(sourcingHistoryProvider(historyKey)).value ??
        const <PastSourcing>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      color: AppColors.grisClair,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.history, size: 18),
              SizedBox(width: 6),
              Text('Déjà sourcé', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            for (final p in items)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      [
                        '${_supplierName(p.source)} — '
                            '${Formatters.date(p.createdAt)}',
                        [
                          if (p.partRef != null) 'réf. ${p.partRef}',
                          if (p.buyPriceKrw != null)
                            Formatters.krw(p.buyPriceKrw),
                          if (p.weightKg != null) '${p.weightKg} kg',
                          if (!p.available) 'indisponible',
                        ].join(' · '),
                        '${p.partName} — ${p.vehicle}'
                            '${p.sameRef ? '' : ' (même pièce, même modèle)'}',
                      ].join('\n'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onReuse(p),
                    child: const Text('Reprendre'),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
