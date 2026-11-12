#!/usr/bin/env python3
"""Gate DAST : échoue si le rapport ZAP (traditional-json) contient des alertes >= seuil.

  python3 security/zap/check_report.py reports/zap-report.json --fail-on high \
      --allowlist security/zap/allowlist.json
"""
import argparse
import json
import sys
from datetime import date

LEVELS = {"info": 0, "low": 1, "medium": 2, "high": 3}
RISKCODE = {"0": "info", "1": "low", "2": "medium", "3": "high"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--fail-on", default="high", choices=LEVELS)
    ap.add_argument("--allowlist", default=None)
    a = ap.parse_args()

    allowed = {}
    if a.allowlist:
        for e in json.load(open(a.allowlist)).get("exceptions", []):
            # une exception expirée n'est plus valable
            if date.fromisoformat(e["expires"]) >= date.today():
                allowed[str(e["pluginid"])] = e["reason"]

    report = json.load(open(a.report))
    threshold = LEVELS[a.fail_on]
    blocking, accepted, summary = [], [], {k: 0 for k in LEVELS}

    for site in report.get("site", []):
        for alert in site.get("alerts", []):
            risk = RISKCODE.get(str(alert.get("riskcode")), "info")
            summary[risk] += 1
            if LEVELS[risk] < threshold:
                continue
            item = f"[{risk.upper()}] {alert['name']} (plugin {alert['pluginid']}) - {len(alert.get('instances', []))} instance(s)"
            if str(alert["pluginid"]) in allowed:
                accepted.append(item + f" - accepté : {allowed[str(alert['pluginid'])]}")
            else:
                blocking.append(item)

    print("Alertes ZAP :", ", ".join(f"{k}={v}" for k, v in summary.items()))
    for i in accepted:
        print("  ~", i)
    for i in blocking:
        print("  x", i)
    if blocking:
        print(f"\nDAST ÉCHEC : {len(blocking)} alerte(s) >= {a.fail_on}")
        sys.exit(1)
    print("\nDAST OK")


if __name__ == "__main__":
    main()
