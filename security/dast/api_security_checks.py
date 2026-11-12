#!/usr/bin/env python3
"""
DAST applicatif (complément à OWASP ZAP) : contrôles d'autorisation et de logique métier
qu'un scanner générique ne sait pas faire sans connaître les rôles de l'application.

  python3 security/dast/api_security_checks.py --base-url http://localhost:8080 \
      --report reports/api-security-checks.json

Sortie : code 1 si au moins un contrôle échoue. Dépendances : stdlib uniquement.
À exécuter UNIQUEMENT sur un environnement jetable ou de staging (crée des tentatives de login).
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

RESULTS = []


def call(base, method, path, token=None, body=None, headers=None, raw=None):
    url = base.rstrip("/") + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if body is not None or raw is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, dict(r.headers), r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode("utf-8", "replace")


def check(name, ok, detail="", severity="high"):
    RESULTS.append({"check": name, "passed": bool(ok), "severity": severity, "detail": detail})
    print(f"[{'PASS' if ok else 'FAIL'}] ({severity}) {name}" + (f" -> {detail}" if detail and not ok else ""))


def login(base, email, password):
    st, _, body = call(base, "POST", "/api/auth/login", body={"email": email, "password": password})
    if st != 200:
        raise SystemExit(f"Login impossible pour {email}: HTTP {st} {body[:200]}")
    return json.loads(body)["access_token"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--admin", default="admin@taskflow.local:admin123")
    ap.add_argument("--member", default="member@taskflow.local:member123")
    ap.add_argument("--report", default="reports/api-security-checks.json")
    ap.add_argument("--skip-rate-limit", action="store_true")
    a = ap.parse_args()
    base = a.base_url

    admin_t = login(base, *a.admin.split(":", 1))
    member_t = login(base, *a.member.split(":", 1))

    # 1. Disponibilité
    st, _, _ = call(base, "GET", "/up")
    check("Health endpoint /up répond 200", st == 200, f"HTTP {st}", "medium")

    # 2. Authentification obligatoire sur toutes les routes protégées
    protected = [
        ("GET", "/api/todos"), ("POST", "/api/todos"), ("GET", "/api/projects"), ("POST", "/api/projects"),
        ("GET", "/api/users"), ("POST", "/api/users"), ("GET", "/api/dashboard"), ("GET", "/api/analytics"),
        ("GET", "/api/search?q=a"), ("GET", "/api/notifications"), ("GET", "/api/saved-views"),
        ("GET", "/api/activity"), ("GET", "/api/audit-log"), ("GET", "/api/auth/me"),
    ]
    bad = [f"{m} {p}={call(base, m, p)[0]}" for m, p in protected if call(base, m, p)[0] != 401]
    check("Routes protégées refusent l'accès anonyme (401)", not bad, "; ".join(bad))

    bad = [p for p in ("/api/todos", "/api/users") if call(base, "GET", p, token="invalid.token.value")[0] != 401]
    check("Jeton invalide refusé (401)", not bad, ",".join(bad))

    # 3. En-têtes de sécurité de l'API
    st, h, _ = call(base, "GET", "/api/auth/me", token=admin_t)
    hl = {k.lower(): v for k, v in h.items()}
    check("X-Content-Type-Options: nosniff", hl.get("x-content-type-options") == "nosniff", str(hl.get("x-content-type-options")), "medium")
    check("X-Frame-Options présent", "x-frame-options" in hl or "frame-ancestors" in hl.get("content-security-policy", ""), "", "medium")
    check("Cache-Control: no-store sur l'API", "no-store" in hl.get("cache-control", ""), hl.get("cache-control", ""), "medium")
    check("Pas de fuite de version (X-Powered-By)", "x-powered-by" not in hl, hl.get("x-powered-by", ""), "low")

    # 4. Anti-énumération de comptes
    _, _, b1 = call(base, "POST", "/api/auth/login", body={"email": "inconnu@example.com", "password": "x"})
    _, _, b2 = call(base, "POST", "/api/auth/login", body={"email": "member@taskflow.local", "password": "mauvais"})
    m1 = json.loads(b1).get("errors", {}) if b1.startswith("{") else b1
    m2 = json.loads(b2).get("errors", {}) if b2.startswith("{") else b2
    check("Login : même message pour compte inconnu / mauvais mot de passe", m1 == m2, f"{m1} vs {m2}")

    # 5. Contrôle d'accès par rôle (membre != admin)
    probes = [
        ("POST", "/api/users", {"name": "x", "email": "x@x.io", "password": "Passw0rd!x", "role": "admin"}),
        ("POST", "/api/projects", {"name": "pwn"}),
    ]
    bad = [f"{m} {p}={call(base, m, p, member_t, body)[0]}" for m, p, body in probes if call(base, m, p, member_t, body)[0] != 403]
    check("Rôle member : écritures admin/manager interdites (403)", not bad, "; ".join(bad))

    st, _, body = call(base, "GET", "/api/users", member_t)
    uid_admin = None
    if st == 200:
        users = json.loads(body)
        users = users.get("data", users) if isinstance(users, dict) else users
        uid_admin = next((u["id"] for u in users if u.get("role") == "admin"), None)
    if uid_admin:
        st1, _, _ = call(base, "PUT", f"/api/users/{uid_admin}", member_t, {"name": "hacked"})
        st2, _, _ = call(base, "DELETE", f"/api/users/{uid_admin}", member_t)
        check("Rôle member : modification/suppression d'un admin interdites", st1 == 403 and st2 == 403, f"PUT={st1} DELETE={st2}")
        # le listing ne doit pas exposer de secrets
        leaked = any(k in json.loads(body).__str__() for k in ("password", "remember_token"))
        check("GET /users n'expose ni password ni remember_token", not leaked, "", "high")

    # 6. Élévation de privilèges par mass-assignment
    call(base, "PUT", "/api/auth/profile", member_t, {"name": "Team Member", "email": "member@taskflow.local", "role": "admin"})
    _, _, me = call(base, "GET", "/api/auth/me", member_t)
    role = json.loads(me).get("user", {}).get("role")
    check("Mass-assignment : un member ne peut pas se promouvoir admin", role == "member", f"role={role}", "critical")

    # 7. IDOR : un membre ne doit pas lire un projet dont il n'est pas membre
    _, _, pb = call(base, "GET", "/api/projects", admin_t)
    projects = json.loads(pb)
    projects = projects.get("data", projects) if isinstance(projects, dict) else projects
    _, _, mb = call(base, "GET", "/api/projects", member_t)
    mine = json.loads(mb)
    mine = mine.get("data", mine) if isinstance(mine, dict) else mine
    mine_ids = {p["id"] for p in mine}
    foreign = [p for p in projects if p["id"] not in mine_ids]
    if foreign:
        codes = [call(base, "GET", f"/api/projects/{p['id']}", member_t)[0] for p in foreign]
        check("IDOR : projet d'autrui inaccessible à un member", all(c in (403, 404) for c in codes), f"codes={codes}", "critical")
    else:
        check("IDOR : projet d'autrui (aucun projet étranger dans le jeu de données)", True, "", "info")

    # 8. Gestion d'erreurs : pas de stack trace
    st, _, b = call(base, "GET", "/api/route-inexistante", admin_t)
    check("404 sans stack trace", st == 404 and "vendor/" not in b and '"trace"' not in b, f"HTTP {st}", "medium")
    st, _, b = call(base, "POST", "/api/todos", admin_t, raw=b"{not-json")
    check("JSON invalide -> 4xx sans fuite technique", 400 <= st < 500 and "vendor/" not in b and '"trace"' not in b, f"HTTP {st}", "medium")

    # 9. Injection : payloads SQLi/XSS ne provoquent ni 500 ni erreur SQL
    sink = []
    for payload in ("' OR '1'='1' --", "1; DROP TABLE users;--", "<script>alert(1)</script>", "%00"):
        st, _, b = call(base, "GET", "/api/search?q=" + urllib.request.quote(payload), admin_t)
        if st >= 500 or "SQLSTATE" in b or "syntax error" in b.lower():
            sink.append(f"{payload!r}->{st}")
        st, _, b = call(base, "GET", "/api/todos?search=" + urllib.request.quote(payload), admin_t)
        if st >= 500 or "SQLSTATE" in b:
            sink.append(f"todos {payload!r}->{st}")
    check("Payloads SQLi/XSS ne déclenchent ni 500 ni erreur SQL", not sink, "; ".join(sink), "critical")

    # 10. CORS : jamais d'origine arbitraire réfléchie
    _, h, _ = call(base, "GET", "/api/auth/me", admin_t, headers={"Origin": "https://evil.example"})
    acao = {k.lower(): v for k, v in h.items()}.get("access-control-allow-origin", "")
    check("CORS : origine inconnue non autorisée", acao not in ("*", "https://evil.example"), acao, "high")

    # 11. Déconnexion : le jeton doit être révoqué
    tmp = login(base, *a.member.split(":", 1))
    call(base, "POST", "/api/auth/logout", tmp)
    st, _, _ = call(base, "GET", "/api/auth/me", tmp)
    check("Jeton révoqué après logout (401)", st == 401, f"HTTP {st}")

    # 12. Anti brute-force : throttling du login (garder en dernier, bloque l'IP quelques minutes)
    if not a.skip_rate_limit:
        codes = [call(base, "POST", "/api/auth/login", body={"email": "brute@force.io", "password": f"p{i}"})[0] for i in range(15)]
        check("Brute-force : le login est limité (429)", 429 in codes, f"codes={sorted(set(codes))}")

    failed = [r for r in RESULTS if not r["passed"]]
    import os
    os.makedirs(os.path.dirname(a.report) or ".", exist_ok=True)
    with open(a.report, "w") as f:
        json.dump({"total": len(RESULTS), "failed": len(failed), "results": RESULTS}, f, indent=2)
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} contrôles réussis")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
