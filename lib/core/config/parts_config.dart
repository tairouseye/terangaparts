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

  /// URL a ouvrir : recherche pre-remplie si possible, sinon le site.
  String urlFor(String? reference) {
    final ref = reference?.trim() ?? '';
    if (searchUrlTemplate != null && ref.isNotEmpty) {
      return searchUrlTemplate!.replaceAll('{q}', Uri.encodeComponent(ref));
    }
    return siteUrl;
  }
}

class PartsConfig {
  const PartsConfig._();

  /// Taux par defaut USD -> KRW propose dans le formulaire de sourcing
  /// (modifiable a la saisie). Le devis client reste calcule en KRW -> FCFA
  /// par le serveur (table `settings`).
  static const num defaultUsdToKrw = 1400;

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
      note: 'Séoul — pièces d\'origine Hyundai, Kia, KGM. Devis par WhatsApp, '
          'remises pour acheteurs réguliers.',
      siteUrl: 'https://seoul-autoparts.com',
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
