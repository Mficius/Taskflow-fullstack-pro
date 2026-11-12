#!/usr/bin/env bash
# Lance le DAST complet en local (stack éphémère + contrôles API + ZAP). Nécessite Docker.
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=http://localhost:8080
mkdir -p reports && chmod 777 reports
trap 'docker compose -f docker-compose.dast.yml down -v' EXIT
docker compose -f docker-compose.dast.yml up -d --build --wait
TOKEN=$(curl -fsS -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"admin@taskflow.local","password":"admin123"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
python3 security/dast/api_security_checks.py --base-url "$BASE" --report reports/api-security-checks.json --skip-rate-limit
docker run --rm --network host -v "$PWD":/zap/wrk:rw -e ZAP_AUTH_TOKEN="$TOKEN" -e TARGET_URL="$BASE" \
  ghcr.io/zaproxy/zaproxy:stable zap.sh -cmd -autorun /zap/wrk/security/zap/plan.yaml || true
python3 security/zap/check_report.py reports/zap-report.json --fail-on "${ZAP_FAIL_ON:-high}" --allowlist security/zap/allowlist.json
echo "Rapports : reports/zap-report.html, reports/api-security-checks.json"
