#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter nu este instalat. Instalează Flutter stable și rulează din nou scriptul."
  exit 1
fi

runner_dir="$(mktemp -d)/lectura_runner"
flutter create \
  --no-pub \
  --platforms=android,ios \
  --org ro.holban \
  --project-name lectura \
  "$runner_dir"

# Copiază numai fișierele native lipsă (inclusiv Gradle wrapper), fără să
# suprascrie configurația, manifestul sau codul Lectura deja existente.
mkdir -p android ios
cp -R -n "$runner_dir/android/." android/
cp -R -n "$runner_dir/ios/." ios/

flutter pub get
flutter doctor

echo "Platformele sunt pregătite. Pentru Android: flutter build apk --release"
