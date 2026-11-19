/// Fournisseurs de pieces detachees utilises pour le sourcing.
///
/// Integration ASSISTEE : l'admin choisit un fournisseur, ouvre son site
/// (recherche pre-remplie quand le site le permet) ou le contacte avec un
/// message pre-rempli (vehicule, VIN, piece), recupere reference + prix,
/// puis saisit la proposition dans l'appli. Aucune donnee n'est aspiree
/// automatiquement depuis ces sites.
///
/// Pour ajouter un fournisseur : ajouter une entree dans [PartsConfig.suppliers].
/// L'identifiant `id` est enregistre dans `suppliers_quotes.source` : ne pas le
/// renommer une fois utilise.
class PartsSupplier {
  /// Identifiant stable (enregistre en base).
  final String id;
  final String name;

  /// Pays / remarque courte affichee a l'admin.
  final String note;

  /// Page d'accueil ou catalogue.
  final String siteUrl;

  /// Recherche par reference, si le site l'expose (`{q}` = reference).
  final String? searchUrlTemplate;

  /// WhatsApp du fournisseur (format international), si connu.
  final String? whatsapp;

  /// Devise dans laquelle le fournisseur affiche ses prix ('KRW' ou 'USD').
  final String currency;

  const PartsSupplier({
    required this.id,
    required this.name,
    required this.note,
    required this.siteUrl,
    this.searchUrlTemplate,
    this.whatsapp,
    this.currency = 'KRW',
  });

  /// Le site sait-il chercher directement une reference ?
  bool get hasSearch => searchUrlTemplate != null;

  /// URL a ouvrir : recherche du site si possible ; sinon recherche Google
  /// limitee au site (« site:sparekorea.com 58101-2SA70 ») ; sans
  /// reference, la page d'accueil.
  String urlFor(String? reference) {
    final ref = reference?.trim() ?? '';
    if (ref.isEmpty) return siteUrl;
    if (searchUrlTemplate != null) {
      return searchUrlTemplate!.replaceAll('{q}', Uri.encodeComponent(ref));
    }
    final host = Uri.parse(siteUrl).host.replaceFirst('www.', '');
    return 'https://www.google.com/search?q='
        '${Uri.encodeComponent('site:$host $ref')}';
  }
}

class PartsConfig {
  const PartsConfig._();

  /// Taux par defaut USD -> KRW propose dans le formulaire de sourcing
  /// (modifiable a la saisie). Le devis client reste calcule en KRW -> FCFA
  /// par le serveur (table `settings`).
  static const num defaultUsdToKrw = 1400;

  /// Catalogue constructeur par VIN (schemas + references exactes du
  /// vehicule) : PartSouq accepte le VIN dans sa recherche.
  static String vinCatalogUrl(String vin) =>
      'https://partsouq.com/en/search/all?q=${Uri.encodeComponent(vin.trim())}';

  static const List<PartsSupplier> suppliers = [
    PartsSupplier(
      id: 'crdi',
      name: 'CRDI.online (KORAVTO)',
      note: 'Incheon, Corée — pièces Hyundai/Kia d\'origine (Mobis), '
          'reconditionnées et occasion. Commandes en gros possibles.',
      siteUrl: 'https://crdi.online',
      // Boutique Shopify : recherche standard par reference.
      searchUrlTemplate: 'https://crdi.online/search?q={q}',
      currency: 'USD',
    ),
    PartsSupplier(
      id: 'seoul_autoparts',
      name: 'Seoul AutoParts',
      note: 'Séoul — 100 % pièces d\'origine Hyundai (OEM). Contact : '
          'Park Jong-hyuk. Prix = coût + 20 % (puis 15 %, puis ~12 % '
          'avec la relation), sous 24 h, sans minimum de commande. Pièces '
          'payées d\'avance ; FedEx facturé au coût après emballage (en '
          'USD). Douane et taxes à la charge de l\'acheteur. Privilégier '
          'les pièces petites et légères.',
      siteUrl: 'https://seoul-autoparts.com',
      whatsapp: '+82 10 7773 7657',
      currency: 'USD',
    ),
    PartsSupplier(
      id: 'sparekorea',
      name: 'Spare Korea',
      note: 'Pièces Hyundai, Kia, SsangYong, GM Korea. Prix en USD. '
          'Ne pas reprendre leur catalogue sans accord écrit.',
      siteUrl: 'https://sparekorea.com',
      currency: 'USD',
    ),
    PartsSupplier(
      id: 'hi_motors',
      name: 'HI-Motors',
      note: 'Corée — conditions à confirmer avec le fournisseur.',
      siteUrl: 'https://hi-motors.com',
      currency: 'USD',
    ),
    PartsSupplier(
      id: 'partsouq',
      name: 'PartSouq',
      note: 'Catalogue de pièces d\'origine multimarques. '
          'Conditions à confirmer.',
      siteUrl: 'https://partsouq.com',
      // Recherche par reference OU par VIN (catalogue constructeur).
      searchUrlTemplate: 'https://partsouq.com/en/search/all?q={q}',
      currency: 'USD',
    ),
    PartsSupplier(
      id: 'partswini',
      name: 'Partswini (Autowini)',
      note: 'Corée — catalogue mobile + fournisseur WhatsApp.',
      siteUrl: 'https://m.autowini.com/Parts/Catalog/parts-search.do',
      whatsapp: '+82 10 2964 5765',
      currency: 'KRW',
    ),
  ];
}
