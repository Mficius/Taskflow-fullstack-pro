#!/usr/bin/env bash
# Évalue les contrôles préventifs (OPA/Conftest) sur un plan Terraform.
# Usage (depuis infrastructure/terraform) : ../../scripts/policy-check.sh tfplan
# Le JSON du plan contient des valeurs sensibles : il n'est jamais conservé ni publié.
set -euo pipefail

PLAN="${1:-tfplan}"
CONFTEST_VERSION="${CONFTEST_VERSION:-0.56.0}"
POLICY_DIR="$(cd "$(dirname "$0")/../infrastructure/policy" && pwd)"

if ! command -v conftest >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" | tar -xz -C "$tmp" conftest
  sudo install "$tmp/conftest" /usr/local/bin/conftest
fi

json="$(mktemp)"
trap 'rm -f "$json"' EXIT
terraform show -json "$PLAN" > "$json"

echo "▶ Tests unitaires des politiques"
conftest verify -p "$POLICY_DIR"

echo "▶ Contrôles préventifs sur le plan"
conftest test --all-namespaces -p "$POLICY_DIR" "$json"
