# Journal des versions — Teranga Parts

La version affichée dans l'application (pied de page, « À propos », page de
connexion) vient de `pubspec.yaml` (`version: X.Y.Z+build`).
À chaque mise en ligne : augmenter la version, ajouter une entrée ici, et
construire avec `--dart-define=BUILD_DATE=AAAA-MM-JJ`.

- **X** (majeure) : changement important de fonctionnement
- **Y** (mineure) : nouvelle fonctionnalité
- **Z** (correctif) : correction sans nouvelle fonctionnalité
- **+build** : augmente de 1 à chaque mise en ligne

## 1.2.1+4 — 2026-11-19
- Connexion : redirection directe vers l'espace du compte après « Se connecter ».
- Liens email (confirmation, mot de passe oublié) : retour toujours vers le site.
- Plus de blocage possible sur l'écran de chargement.
- Version affichée aussi sur le formulaire de demande.

## 1.2.0+3 — 2026-11-19
- Lecture des photos par l'IA : carte grise (VIN, marque, modèle, année) et
  pièce (nom, catégorie, référence constructeur). 30 photos par jour et par
  personne.
- Seoul AutoParts : WhatsApp et conditions dans la fiche fournisseur.

## 1.1.0+2 — 2026-11-19
- Demande de pièce sans compte (session invitée), compte facultatif ensuite.
- Correction de sécurité : le rôle d'un nouveau compte est toujours « client ».

## 1.0.0+1 — 2026-11-19
- Séparation d'avec TerangaMobility : pièces détachées uniquement, nouvelle
  marque, domaine terangaparts.gesprosn.org, projet Supabase dédié.
- Recherche de pièces auprès de plusieurs fournisseurs.
