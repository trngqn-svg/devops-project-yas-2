#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS_DIR="$ROOT_DIR/k8s/charts"

# Build the reusable backend/ui dependency into each application chart first.
charts=(
  product media location customer cart inventory rating promotion tax
  order payment storefront-bff backoffice-bff storefront-ui backoffice-ui
)

for chart in "${charts[@]}"; do
  echo "Building dependencies for $chart"
  helm dependency build "$CHARTS_DIR/$chart"
done

echo "Updating umbrella chart dependencies"
# `update` regenerates Chart.lock when Chart.yaml changes. Using `build` here
# would fail on a fresh clone if a teammate committed an older lock file.
helm dependency update "$CHARTS_DIR/yas-platform"
