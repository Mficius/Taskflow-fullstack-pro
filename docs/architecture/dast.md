# DAST - tests dynamiques

Le DAST attaque l'application **en fonctionnement**, comme un utilisateur malveillant. Il complète le SAST (Semgrep)
qui lit le code. Il se fait en trois temps :

| Étape | Outil | Cible | Nature |
|---|---|---|---|
| 1. Logique & autorisation | `security/dast/api_security_checks.py` (18 contrôles) | stack éphémère | rôles, IDOR, mass-assignment, jetons, brute-force, CORS, fuite d'erreurs, injections |
| 2. Scan applicatif | OWASP ZAP *Automation Framework* (`security/zap/plan.yaml`) | stack éphémère | OpenAPI → 100 % des routes, spider + AJAX spider (SPA), scan **actif**, **authentifié** (Bearer) |
| 3. Contrôle continu | ZAP **passif** (`plan-passive.yaml`) | URL déployée | aucune attaque, sûr en production |

## Pourquoi cette conception
- **Authentifié** : un scanner anonyme ne voit que `/login`. Le jeton d'un admin est injecté (`replacer`) et masqué dans les logs.
- **Contrat OpenAPI** (`docs/api/openapi.yaml`) : couverture exhaustive, pas seulement ce que le crawler trouve.
- **Gate chiffré** : `check_report.py` échoue au-dessus d'un seuil (`high` par défaut, réglable `medium`/`low` en manuel).
  Les exceptions passent par `security/zap/allowlist.json` : justification **et date d'expiration** obligatoires.
- **Jamais d'attaque active sur la production** : la production n'a que le scan passif.
- **Rapports** : HTML + JSON + SARIF (onglet *Security*), conservés 30 jours.

## Contrôles d'autorisation (extrait)
Anonyme → 401 sur toutes les routes · jeton invalide → 401 · `member` → 403 sur écritures admin/manager ·
un `member` ne peut pas se promouvoir `admin` (mass-assignment) · IDOR sur projets d'autrui · pas de
`password`/`remember_token` dans `/users` · message de login identique (anti-énumération) · 429 après 10 essais ·
jeton révoqué après logout · pas de stack-trace sur 404/JSON invalide · payloads SQLi/XSS sans 500 ·
CORS : origine inconnue non autorisée · en-têtes de sécurité et `Cache-Control: no-store`.

## Faux positifs documentés
`plan.yaml` (`alertFilter`) : CSP `style-src 'unsafe-inline'` (MUI/Emotion injecte des `<style>`), et cache des
assets Vite versionnés. Piste d'amélioration : nonces CSP.

## Exécuter
- Stack locale éphémère : `./scripts/dast-local.sh` (tests d'autorisation + ZAP Automation Framework actif/authentifié).
- URL déployée : GitHub Actions → `DAST baseline` → *Run workflow*, avec la variable `APP_URL` configurée. Le workflow planifié chaque semaine utilise le scan baseline passif; il ne lance pas de scan actif sur la production.
