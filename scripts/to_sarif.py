#!/usr/bin/env python3
import json, sys

if len(sys.argv) < 2:
  print("{}")
  sys.exit(0)

inp = sys.argv[1]
data = json.load(open(inp))
results = []

def add_result(tool, rule_id, file, line, severity, msg):
  level = {"ERROR":"error","WARNING":"warning","NOTICE":"note"}.get(severity,"warning")
  results.append({
    "ruleId": f"{tool}/{rule_id}",
    "level": level,
    "message": {"text": msg},
    "locations": [{
      "physicalLocation": {
        "artifactLocation": {"uri": file},
        "region": {"startLine": max(1, int(line or 1))}
      }
    }]
  })

# PHPCS
for file, recs in (data.get("phpcs", {}).get("files", {}) or {}).items():
  for m in recs.get("messages", []):
    add_result("phpcs", m.get("source","rule"), file, m.get("line",1), m.get("type","WARNING"), m.get("message",""))

# PHPCompatibility
for file, recs in (data.get("phpcompat", {}).get("files", {}) or {}).items():
  for m in recs.get("messages", []):
    add_result("phpcompat", m.get("source","rule"), file, m.get("line",1), m.get("type","WARNING"), m.get("message",""))

# Semgrep
for r in (data.get("semgrep", {}).get("results", []) or []):
  path = r.get("path","") or r.get("extra", {}).get("metadata", {}).get("file","")
  start = r.get("start", {}) or r.get("start", {})
  line = (start.get("line", 1) if isinstance(start, dict) else 1)
  msg = r.get("extra", {}).get("message", "") or r.get("extra", {}).get("metadata", {}).get("message","")
  add_result("semgrep", r.get("check_id","rule"), path, line, "WARNING", msg)

# Custom checkers
for k in ["readme_i18n","a11y_static"]:
  for r in (data.get(k, {}).get("results", []) or []):
    add_result(k, r.get("rule","rule"), r.get("file",""), r.get("line",1), r.get("severity","NOTICE"), r.get("message",""))

sarif = {
  "version": "2.1.0",
  "$schema": "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0-rtm.5.json",
  "runs": [{
    "tool": {"driver": {"name": "phantom", "rules": []}},
    "results": results
  }]
}
print(json.dumps(sarif))
