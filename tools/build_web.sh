#!/usr/bin/env bash
# Construit le site Teranga Parts avec la version EMBARQUEE.
#   - APP_VERSION : lue dans pubspec.yaml (« version: X.Y.Z+build »), sert a
#     detecter « Nouvelle version disponible » (comparee a version.json).
#   - BUILD_DATE  : date du jour, affichee a cote de la version.
# Puis prepare build/web pour GitHub Pages (404.html = index.html).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//')
DATE=$(date +%F)
echo "Build Teranga Parts v$VERSION ($DATE)"
flutter build web --release \
  --dart-define=APP_VERSION="$VERSION" \
  --dart-define=BUILD_DATE="$DATE"
cp build/web/index.html build/web/404.html
echo "OK : build/web pret (v$VERSION)"
