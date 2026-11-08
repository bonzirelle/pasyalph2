#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
FLUTTER_HOME="${FLUTTER_HOME:-${HOME}/.cache/pasyalph-flutter-${FLUTTER_VERSION}}"

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  FLUTTER="$FLUTTER_BIN"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER="$(command -v flutter)"
elif [[ -x "${FLUTTER_HOME}/bin/flutter" ]]; then
  FLUTTER="${FLUTTER_HOME}/bin/flutter"
else
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  FLUTTER="${FLUTTER_HOME}/bin/flutter"
fi

export PATH="$(dirname "$FLUTTER"):$PATH"
"$FLUTTER" config --no-analytics
"$FLUTTER" pub get
"$FLUTTER" build web --release --no-pub
