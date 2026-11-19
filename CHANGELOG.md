# Journal des versions — Teranga Parts

Format inspiré de GesSchool : version la plus récente en haut, un titre par
version, des points en français simple.
La version vient de `pubspec.yaml` (`version: X.Y.Z+build`) et s'affiche dans
l'application (pied de page, « À propos », page d'accueil).
À chaque mise en ligne : augmenter la version, ajouter une entrée ici, puis
construire avec `tools/build_web.sh` (version et date embarquées).

- **X** (majeure) : changement important de fonctionnement
- **Y** (mineure) : nouvelle fonctionnalité
- **Z** (correctif) : correction sans nouvelle fonctionnalité
- **+build** : augmente de 1 à chaque mise en ligne

## [1.4.0] — Trouver une pièce plus vite
- **Référence déjà remplie** : quand le client a envoyé une photo de la
  pièce, la référence constructeur lue par l'IA est reprise dans l'écran
  « Sourcer la pièce ». La photo du client s'affiche sur le même écran.
- **Catalogue constructeur par VIN** : un bouton ouvre le catalogue PartSouq
  du véhicule exact (schémas et références d'origine).
- **Tous les fournisseurs sur un écran** : pour chacun, un bouton
  « Chercher » ouvre la recherche de la référence, et un bouton WhatsApp
  envoie le message pré-rempli. Pour les sites sans recherche, c'est une
  recherche Google limitée au site.
- **Messages aux fournisseurs en anglais** (véhicule, VIN, référence,
  quantité ; on demande le prix, le poids et le délai).
- **Déjà sourcé** : les sourcings précédents de la même référence (ou de la
  même pièce sur le même modèle) s'affichent avec le fournisseur, le prix,
  le poids et la date. Un bouton « Reprendre » remplit le formulaire.

## [1.3.1] — Des messages clairs pour la connexion et les emails
- **Messages en français clair** pour la connexion, l'inscription, le mot de
  passe oublié et la création de compte : « Email ou mot de passe
  incorrect », « Trop d'emails envoyés en peu de temps, réessayez dans une
  heure », « Confirmez d'abord votre email »… au lieu de « Envoi impossible ».
- **Inscription** : le message rappelle de confirmer son email avant de se
  connecter (il disait « Vous pouvez vous connecter »).

## [1.3.0] — L'administrateur est prévenu, et l'app aussi
Migration 0021.
- **Alertes automatiques** (mig. 0021) : chaque nouvelle demande arrive dans la
  cloche 🔔 de l'administrateur, avec la pièce, le véhicule et le nom du client.
  Le client est prévenu quand son devis est prêt et à chaque étape de sa
  commande. Les acomptes et soldes déclarés préviennent l'administrateur.
- **À traiter** sur l'accueil administrateur : les demandes à sourcer, les
  pièces à chiffrer et les acomptes à vérifier, de la plus ancienne à la plus
  récente. Chaque ligne a un bouton **Traiter** et un bouton **WhatsApp** vers
  le client. Le bloc se met à jour tout seul quand une demande arrive.
- **Nouvelle version disponible** : un bandeau propose de recharger quand une
  mise à jour est publiée. La version affichée est celle qui tourne vraiment.

## [1.2.1] — 2026-11-19
- Connexion : redirection directe vers l'espace du compte après « Se connecter ».
- Liens email (confirmation, mot de passe oublié) : retour toujours vers le site.
- Plus de blocage possible sur l'écran de chargement.
- Version affichée aussi sur le formulaire de demande.

## [1.2.0] — 2026-11-19
- Lecture des photos par l'IA : carte grise (VIN, marque, modèle, année) et
  pièce (nom, catégorie, référence constructeur). 30 photos par jour et par
  personne.
- Seoul AutoParts : WhatsApp et conditions dans la fiche fournisseur.

## [1.1.0] — 2026-11-19
- Demande de pièce sans compte (session invitée), compte facultatif ensuite.
- Correction de sécurité : le rôle d'un nouveau compte est toujours « client ».

## [1.0.0] — 2026-11-19
- Séparation d'avec TerangaMobility : pièces détachées uniquement, nouvelle
  marque, domaine terangaparts.gesprosn.org, projet Supabase dédié.
- Recherche de pièces auprès de plusieurs fournisseurs.
