# Teranga Parts

Marketplace de pièces détachées coréennes (Hyundai, Kia, SsangYong, GM Korea),
livrées au Sénégal. Marque **indépendante** de TerangaMobility depuis la
séparation de novembre 2026 : le module d'import de véhicules (Encar) reste
chez TerangaMobility.

Flutter (Android / iOS / Web) + Supabase (Auth, PostgreSQL, Storage, RLS).

## Fournisseurs

Le sourcing est **assisté** : l'admin choisit un fournisseur, ouvre son site ou
lui envoie un message pré-rempli (véhicule, VIN, pièce), puis saisit le prix.
Aucune donnée n'est aspirée automatiquement. Liste dans
`lib/core/config/parts_config.dart` : CRDI.online (KORAVTO), Seoul AutoParts,
Spare Korea, HI-Motors, PartSouq, Partswini. Les prix en USD sont convertis en
KRW à la saisie (taux modifiable), puis le serveur calcule le devis en FCFA.

## Architecture

Feature-first, 3 couches : **UI → Provider (Riverpod) → Service (Supabase)**.

```
lib/
├── core/        config, thème (Rouge/Vert/Blanc), router+guards, widgets, utils
├── models/      DTO typés + enums (13 statuts, rôles, paiement)
├── services/    auth_service, storage_service (+ à venir)
├── providers/   providers Riverpod (auth, session, profil/rôle)
└── features/
    ├── auth/        splash, login, signup (choix rôle)
    ├── client/      espace client
    ├── partner_kr/  espace partenaire Corée
    ├── admin/       espace admin
    └── shared/      ossature commune des dashboards
supabase/migrations/  schéma SQL versionné (tables + RLS + fonction devis)
lib/demo/             mode démo hors-ligne (données en mémoire, sans Supabase)
```

## Mode démo (sans Supabase)

Pour explorer l'app **sans aucun backend**, avec des données fictives en mémoire :

```
flutter run -t lib/main_demo.dart
```

(fonctionne sur Chrome, un émulateur ou en desktop). Un écran d'accueil permet
de choisir l'espace **Client / Partenaire Corée / Admin**. Les actions
(ajouter un véhicule, déposer une demande, chiffrer un devis, payer l'acompte,
faire avancer une commande…) sont fonctionnelles et se répercutent entre écrans,
mais rien n'est persisté : tout repart à zéro au redémarrage.

## Déploiement (GitHub Pages)

- **Prod** : https://terangaparts.gesprosn.org
- Dépôt GitHub : **à créer** (dépôt propre à Teranga Parts, distinct de
  `tairouseye/terangamobility`).
- DNS : CNAME `terangaparts` → `<compte>.github.io` (Cloudflare, **DNS only**).

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
cd build/web && cp index.html 404.html   # routage SPA sur GitHub Pages
```
Puis publier `build/web` sur la branche `gh-pages` du dépôt Teranga Parts
(`web/CNAME` contient déjà `terangaparts.gesprosn.org`).

> Sans `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY`, l'app affiche un message
> « projet non configuré » et n'ouvre aucune connexion.

## Mise en route

### 1. Créer le projet Supabase
Un **projet Supabase dédié** à Teranga Parts (pas celui de TerangaMobility).

### 2. Appliquer le schéma
Avec la CLI, depuis ce dossier : `npx supabase link --project-ref <ref>`, puis
`npx supabase db push --dry-run`, puis `npx supabase db push`.
Les migrations ne contiennent que le module pièces (tables, RLS, devis,
acompte/solde, notifications, buckets `documents` et `parts`).

### 3. Renseigner les clés
Dans `lib/core/config/supabase_config.dart`, renseigner les `defaultValue`
(URL du projet + clé **publishable**, jamais la clé `service_role`), **ou**
lancer avec :
```
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

### 4. Promouvoir un admin
Les inscriptions créent des rôles `client` ou `partner_kr`. Pour un admin :
```sql
update profiles set role = 'admin' where id = '<uid>';
```

## Modèle de devis (serveur)

`total = prix_pièce + FedEx(poids) + douane(grille) + commission`

Calculé par `compute_customer_quote()` à partir de `settings`
(taux KRW→FCFA, coût FedEx/kg, % commission) et `customs_rates`.
Paiement **70 % acompte / 30 % solde**.

## État d'avancement (MVP)

- [x] **Lot 0** — Scaffold : projet, thème, config, schéma SQL + RLS, auth 3 rôles
- [ ] Lot 1 — Auth finalisée (reset mot de passe)
- [x] **Lot 2** — Véhicules (CRUD + upload carte grise)
- [x] **Lot 3** — Demande de pièce (formulaire + photo + liste/statut)
- [x] **Lot 4** — Espace partenaire Corée (inbox demandes + propositions)
- [x] **Lot 5** — Devis chiffré (compute serveur) + validation client
- [x] **Lot 6** — Acompte 70 % (fonction `pay_deposit` → commande)
- [x] **Lot 7** — Suivi commande (timeline 13 statuts), solde 30 % (`pay_balance`), pilotage admin (statuts + expédition FedEx)

**MVP fonctionnel complet.** Reste hors-MVP : Lot 1 (reset mot de passe), intégration paiement PSP (Wave API…), notifications WhatsApp, module admin clients/paramètres douane.
