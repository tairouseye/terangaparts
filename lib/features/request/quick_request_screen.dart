import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/fb_pixel.dart';
import '../../core/config/app_info.dart';
import '../../core/data/part_catalog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/open_tab.dart';
import '../../core/widgets/teranga_logo.dart';
import '../../models/parts_request.dart';
import '../../models/vehicle.dart';
import '../../providers/auth_providers.dart';
import '../../providers/request_providers.dart';
import '../../providers/vehicle_providers.dart';
import '../../services/photo_analysis_service.dart';
import 'create_account_screen.dart';

/// Marques proposees (vehicules coreens).
const _brands = [
  'Hyundai',
  'Kia',
  'Genesis',
  'SsangYong / KGM',
  'Chevrolet / Daewoo (GM Korea)',
  'Renault Samsung',
  'Autre',
];

/// Demande de piece en UNE page, SANS compte obligatoire.
///
/// Visiteur : a l'envoi, une session invitee est ouverte (nom + WhatsApp),
/// puis la demande est enregistree. Le compte (email + mot de passe) est
/// facultatif et se cree apres coup, en gardant les demandes.
/// Client connecte : coordonnees et vehicules pre-remplis.
class QuickRequestScreen extends ConsumerStatefulWidget {
  const QuickRequestScreen({super.key});

  @override
  ConsumerState<QuickRequestScreen> createState() =>
      _QuickRequestScreenState();
}

class _QuickRequestScreenState extends ConsumerState<QuickRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  // Vehicule
  String? _brand;
  final _otherBrand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _vin = TextEditingController();
  Vehicle? _savedVehicle; // vehicule deja enregistre choisi (client connu)
  bool _useNewVehicle = false;
  // Piece
  String? _category;
  String? _selectedPart;
  final _customPart = TextEditingController();
  final _notes = TextEditingController();
  XFile? _photo;
  // Contact
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  bool _contactPrefilled = false;

  // Lecture des photos par l'IA
  bool _readingVin = false;
  bool _readingPart = false;
  String? _vinInfo; // resultat / conseil affiche sous le bouton
  bool _vinOk = false;
  String? _partInfo;
  bool _partOk = false;

  bool _saving = false;
  String? _error;

  /// Rapproche la marque lue de la liste proposee.
  String? _matchBrand(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final r = raw.toLowerCase();
    for (final b in _brands) {
      final first = b.split(RegExp(r'[ /(]')).first.toLowerCase();
      if (first.isNotEmpty && r.contains(first)) return b;
    }
    if (r.contains('kgm')) return 'SsangYong / KGM';
    if (r.contains('daewoo') || r.contains('gm')) {
      return 'Chevrolet / Daewoo (GM Korea)';
    }
    if (r.contains('samsung')) return 'Renault Samsung';
    return null;
  }

  Future<XFile?> _pickImage() => ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);

  /// Photo de la carte grise (ou du VIN) -> remplit le vehicule.
  Future<void> _scanVin() async {
    final img = await _pickImage();
    if (img == null) return;
    setState(() {
      _readingVin = true;
      _vinInfo = null;
    });
    try {
      await ref.read(authServiceProvider).ensureSession();
      final bytes = await img.readAsBytes();
      final r = await ref.read(photoAnalysisServiceProvider).readVin(
          bytes, PhotoAnalysisService.mediaTypeFor(img.name, img.mimeType));
      final brand = _matchBrand(r.brand);
      setState(() {
        _useNewVehicle = true;
        if (r.vin != null) _vin.text = r.vin!;
        if (brand != null) {
          _brand = brand;
        } else if (r.brand != null && r.brand!.trim().isNotEmpty) {
          _brand = 'Autre';
          _otherBrand.text = r.brand!.trim();
        }
        if (r.model != null) _model.text = r.model!;
        if (r.year != null) _year.text = '${r.year}';
        _vinOk = r.vin != null;
        _vinInfo = r.vin != null
            ? 'VIN lu : ${r.vin}. Vérifiez les informations ci-dessous.'
            : (r.note ??
                'VIN non lisible. Essayez une photo plus nette ou '
                    'saisissez-le à la main.');
      });
    } on PhotoAnalysisException catch (e) {
      setState(() {
        _vinOk = false;
        _vinInfo = e.message;
      });
    } catch (_) {
      setState(() {
        _vinOk = false;
        _vinInfo = 'Lecture impossible. Saisissez les informations à la main.';
      });
    } finally {
      if (mounted) setState(() => _readingVin = false);
    }
  }

  /// Photo de la piece -> identifie la piece (et la joint a la demande).
  Future<void> _scanPart() async {
    final img = await _pickImage();
    if (img == null) return;
    setState(() {
      _photo = img; // jointe a la demande dans tous les cas
      _readingPart = true;
      _partInfo = null;
    });
    try {
      await ref.read(authServiceProvider).ensureSession();
      final bytes = await img.readAsBytes();
      final r = await ref.read(photoAnalysisServiceProvider).readPart(
            bytes,
            PhotoAnalysisService.mediaTypeFor(img.name, img.mimeType),
            catalog: PartCatalog.catalog,
          );
      if (!r.isAutoPart) {
        setState(() {
          _partOk = false;
          _partInfo = r.note ??
              'Nous ne reconnaissons pas de pièce sur cette photo. '
                  'Choisissez la pièce dans la liste.';
        });
        return;
      }
      setState(() {
        final cat = PartCatalog.categories.contains(r.category)
            ? r.category!
            : 'Autre';
        _category = cat;
        final match = r.catalogMatch;
        if (cat != 'Autre' &&
            match != null &&
            PartCatalog.partsFor(cat).contains(match)) {
          _selectedPart = match;
        } else {
          _selectedPart = cat == 'Autre' ? null : PartCatalog.autre;
          _customPart.text = r.partName ?? '';
        }
        final extras = <String>[
          if (r.oemPartNumber != null) 'Réf. lue sur la photo : ${r.oemPartNumber}',
          if (r.sideOrPosition != null) 'Position : ${r.sideOrPosition}',
        ];
        if (extras.isNotEmpty) {
          final existing = _notes.text.trim();
          _notes.text = [if (existing.isNotEmpty) existing, ...extras].join('\n');
        }
        _partOk = true;
        _partInfo = 'Pièce reconnue : ${r.partName ?? match ?? cat}'
            '${r.oemPartNumber != null ? ' (réf. ${r.oemPartNumber})' : ''}. '
            '${r.note ?? 'Vérifiez ci-dessous.'}';
      });
    } on PhotoAnalysisException catch (e) {
      setState(() {
        _partOk = false;
        _partInfo = '${e.message} La photo reste jointe à votre demande.';
      });
    } catch (_) {
      setState(() {
        _partOk = false;
        _partInfo = 'Lecture impossible. La photo reste jointe à votre '
            'demande : choisissez la pièce dans la liste.';
      });
    } finally {
      if (mounted) setState(() => _readingPart = false);
    }
  }

  bool get _needsCustom =>
      _category == 'Autre' || _selectedPart == PartCatalog.autre;

  String get _partName =>
      _needsCustom ? _customPart.text.trim() : (_selectedPart ?? '');

  String get _brandName =>
      _brand == 'Autre' ? _otherBrand.text.trim() : (_brand ?? '');

  @override
  void dispose() {
    for (final c in [
      _otherBrand,
      _model,
      _year,
      _vin,
      _customPart,
      _notes,
      _name,
      _whatsapp
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partName.isEmpty) {
      setState(() => _error = 'Choisissez ou précisez la pièce recherchée.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    final name = _name.text.trim();
    final phone = _whatsapp.text.trim();
    try {
      // 1. Session : invite si personne n'est connecte.
      if (auth.currentUser == null) {
        await auth.signInAsGuest(fullName: name, whatsapp: phone);
      } else {
        await auth.updateContact(fullName: name, whatsapp: phone);
      }
      final uid = auth.currentUser!.id;

      // 2. Vehicule : choisi parmi les enregistres, ou nouveau (enregistre
      //    pour les prochaines demandes).
      Vehicle? vehicle = _useNewVehicle ? null : _savedVehicle;
      vehicle ??= await ref.read(vehicleServiceProvider).upsert(Vehicle(
            userId: uid,
            brand: _brandName,
            model: _model.text.trim(),
            year: int.tryParse(_year.text.trim()),
            vin: _vin.text.trim().isEmpty
                ? null
                : _vin.text.trim().toUpperCase(),
          ));

      // 3. Photo facultative.
      String? photoUrl;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        final ext = _photo!.name.split('.').last;
        photoUrl = await ref
            .read(storageServiceProvider)
            .uploadPartPhoto(uid, bytes, ext: ext.isEmpty ? 'jpg' : ext);
      }

      // 4. Demande (instantane du vehicule fige pour le sourcing).
      await ref.read(requestServiceProvider).create(PartsRequest(
            clientId: uid,
            vehicleId: vehicle.id,
            partName: _partName,
            partPhotoUrl: photoUrl,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            vehicleBrand: vehicle.brand,
            vehicleModel: vehicle.model,
            vehicleYear: vehicle.year,
            vehicleEngine: vehicle.engine,
            vehicleVin: vehicle.vin,
          ));

      fbTrack('Lead', {'content_type': 'product', 'content_name': _partName});
      ref.invalidate(myRequestsProvider);
      ref.invalidate(myVehiclesProvider);
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RequestSentScreen(
          partName: _partName,
          vehicleLabel: vehicle!.label,
          isGuest: auth.isGuest,
        ),
      ));
    } catch (e) {
      setState(() => _error =
          'Envoi impossible. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _prefillContact() {
    if (_contactPrefilled) return;
    final p = ref.read(currentProfileProvider).valueOrNull;
    if (p == null) return;
    _contactPrefilled = true;
    if (_name.text.isEmpty) _name.text = p.fullName;
    if (_whatsapp.text.isEmpty) _whatsapp.text = p.whatsapp;
  }

  @override
  Widget build(BuildContext context) {
    // Se reconstruit a chaque changement d'auth (connexion, session invitee).
    ref.watch(authStateProvider);
    final loggedIn = ref.watch(authServiceProvider).currentUser != null;
    if (loggedIn) _prefillContact();
    final vehicles = loggedIn
        ? (ref.watch(myVehiclesProvider).valueOrNull ?? const <Vehicle>[])
        : const <Vehicle>[];
    if (vehicles.isNotEmpty && _savedVehicle == null && !_useNewVehicle) {
      _savedVehicle = vehicles.first;
    }
    final showVehicleFields = vehicles.isEmpty || _useNewVehicle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demander une pièce'),
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        actions: [
          if (!loggedIn)
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('Se connecter'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (!loggedIn) ...[
                    const Center(child: TerangaLogo(width: 200)),
                    const SizedBox(height: 12),
                    const Text(
                      'Dites-nous quelle pièce il vous faut : nous la trouvons '
                      'en Corée et vous envoyons un devis sur WhatsApp. '
                      'Sans engagement, sans créer de compte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gris, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ---------------- 1. Vehicule ----------------
                  const _StepTitle(n: 1, title: 'Votre véhicule'),
                  _PhotoScanButton(
                    icon: Icons.document_scanner,
                    label: 'Photo de la carte grise',
                    hint: 'Nous lisons le VIN, la marque et l\'année pour vous.',
                    busy: _readingVin,
                    onTap: _scanVin,
                    info: _vinInfo,
                    ok: _vinOk,
                  ),
                  const SizedBox(height: 12),
                  if (vehicles.isNotEmpty) ...[
                    DropdownButtonFormField<Object>(
                      key: ValueKey('veh-$_useNewVehicle'),
                      initialValue: _useNewVehicle ? 'new' : _savedVehicle,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Véhicule'),
                      items: [
                        for (final v in vehicles)
                          DropdownMenuItem(value: v, child: Text(v.label)),
                        const DropdownMenuItem(
                            value: 'new', child: Text('+ Autre véhicule')),
                      ],
                      onChanged: (v) => setState(() {
                        _useNewVehicle = v == 'new';
                        if (v is Vehicle) _savedVehicle = v;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showVehicleFields) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('brand-$_brand'),
                      initialValue: _brand,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Marque *'),
                      items: [
                        for (final b in _brands)
                          DropdownMenuItem(value: b, child: Text(b)),
                      ],
                      validator: (v) => v == null ? 'Choisissez la marque' : null,
                      onChanged: (v) => setState(() => _brand = v),
                    ),
                    if (_brand == 'Autre') ...[
                      const SizedBox(height: 12),
                      _text(_otherBrand, 'Précisez la marque *', required: true),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: _text(_model, 'Modèle *',
                            hint: 'Ex : Tucson, Sportage', required: true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _text(_year, 'Année',
                            hint: '2016',
                            keyboard: TextInputType.number),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _text(_vin, 'N° de châssis (VIN) — conseillé',
                        hint: 'Sur la carte grise, 17 caractères',
                        caps: TextCapitalization.characters),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Le VIN nous permet de trouver la référence exacte.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.gris),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ---------------- 2. Piece ----------------
                  const _StepTitle(n: 2, title: 'La pièce recherchée'),
                  _PhotoScanButton(
                    icon: Icons.photo_camera,
                    label: _photo != null
                        ? 'Changer la photo de la pièce'
                        : 'Photo de la pièce',
                    hint: 'Nous reconnaissons la pièce et sa référence si '
                        'elle est visible. La photo est jointe à la demande.',
                    busy: _readingPart,
                    onTap: _scanPart,
                    info: _partInfo,
                    ok: _partOk,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cat-$_category'),
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Catégorie *'),
                    items: [
                      for (final c in PartCatalog.categories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    validator: (v) =>
                        v == null ? 'Choisissez une catégorie' : null,
                    onChanged: (c) => setState(() {
                      _category = c;
                      _selectedPart = null;
                    }),
                  ),
                  if (_category != null && _category != 'Autre') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('part-$_category-$_selectedPart'),
                      initialValue: _selectedPart,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Pièce *'),
                      items: [
                        for (final p in PartCatalog.partsFor(_category!))
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (p) => setState(() => _selectedPart = p),
                    ),
                  ],
                  if (_needsCustom) ...[
                    const SizedBox(height: 12),
                    _text(_customPart, 'Précisez la pièce *',
                        hint: 'Ex : support de boîte de vitesses',
                        required: true,
                        caps: TextCapitalization.sentences),
                  ],
                  if (PartCatalog.isOversized(_selectedPart)) ...[
                    const SizedBox(height: 12),
                    const OversizeWarning(),
                  ],
                  const SizedBox(height: 12),
                  _text(_notes, 'Précisions (facultatif)',
                      hint: 'Référence connue, côté (gauche/droite), état…',
                      maxLines: 2,
                      caps: TextCapitalization.sentences),
                  const SizedBox(height: 24),
                  // ---------------- 3. Contact ----------------
                  const _StepTitle(n: 3, title: 'Où vous envoyer le devis ?'),
                  _text(_name, 'Votre nom *',
                      required: true, caps: TextCapitalization.words),
                  const SizedBox(height: 12),
                  _text(_whatsapp, 'Numéro WhatsApp *',
                      hint: '77 123 45 67',
                      keyboard: TextInputType.phone,
                      validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.length < 9 ? 'Numéro WhatsApp invalide' : null;
                  }),
                  const SizedBox(height: 16),
                  const ShippingNotice(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Envoyer ma demande'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gratuit et sans engagement. Vous recevez le devis avant '
                    'tout paiement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.gris),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
    TextCapitalization caps = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      textCapitalization: caps,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Obligatoire' : null
              : null),
    );
  }
}

/// Gros bouton « photo » + texte d'aide + resultat de la lecture.
class _PhotoScanButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool busy;
  final VoidCallback onTap;
  final String? info;
  final bool ok;
  const _PhotoScanButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.busy,
    required this.onTap,
    required this.info,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onTap,
          icon: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon),
          label: Text(busy ? 'Lecture de la photo…' : label),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            info == null ? '$hint Ou remplissez à la main.' : info!,
            style: TextStyle(
              fontSize: 12,
              color: info == null
                  ? AppColors.gris
                  : (ok ? AppColors.vert : const Color(0xFF9A6B00)),
              fontWeight: info == null ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  final int n;
  final String title;
  const _StepTitle({required this.n, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.primary,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Confirmation apres envoi : prochaines etapes + compte facultatif.
class RequestSentScreen extends StatelessWidget {
  final String partName;
  final String vehicleLabel;
  final bool isGuest;
  const RequestSentScreen({
    super.key,
    required this.partName,
    required this.vehicleLabel,
    required this.isGuest,
  });

  @override
  Widget build(BuildContext context) {
    final waMessage = 'Bonjour Teranga Parts, je viens de faire une demande '
        'pour : $partName ($vehicleLabel). Je vous envoie une photo.';
    return Scaffold(
      appBar: AppBar(
          title: const Text('Demande envoyée'),
          automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.check_circle, color: AppColors.vert, size: 72),
                const SizedBox(height: 12),
                const Text('Demande bien reçue !',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('$partName — $vehicleLabel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.gris)),
                const SizedBox(height: 20),
                const _NextStep(
                    icon: Icons.search,
                    text: 'Nous recherchons la pièce chez nos fournisseurs '
                        'en Corée.'),
                const _NextStep(
                    icon: Icons.chat,
                    text: 'Vous recevez le devis détaillé (pièce, transport, '
                        'douane) sur WhatsApp.'),
                const _NextStep(
                    icon: Icons.payments,
                    text: 'Vous validez et payez un acompte de 70 % pour '
                        'lancer la commande. Le solde à l\'arrivée.'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      openInNewTab(AppInfo.whatsappSales(waMessage)),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Envoyer une photo sur WhatsApp'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => context.go('/client'),
                  icon: const Icon(Icons.inventory_2),
                  label: const Text('Suivre ma demande'),
                ),
                if (isGuest) ...[
                  const SizedBox(height: 24),
                  const GuestAccountCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  final IconData icon;
  final String text;
  const _NextStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text, style: const TextStyle(height: 1.35))),
        ]),
      );
}

/// Rappel : seules les pieces expediables en express sont traitees.
class ShippingNotice extends StatelessWidget {
  const ShippingNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.vert.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.vert.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_shipping, color: AppColors.vert, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pièces expédiables par messagerie express (FedEx, DHL…). '
              'Les pièces très volumineuses ou lourdes ne peuvent pas être '
              'acheminées.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avertissement : piece souvent hors gabarit pour l'express.
class OversizeWarning extends StatelessWidget {
  const OversizeWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ambre.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ambre.withValues(alpha: 0.5)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB07C00), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cette pièce est souvent trop volumineuse pour un envoi express. '
              'Envoyez quand même la demande : nous vérifions la faisabilité '
              'et le coût avant tout devis.',
              style: TextStyle(
                  color: Color(0xFF7A5A00), fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
