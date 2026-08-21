#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

echo "configs:"

[ -f .env ]
check ".env exists" $?

# shellcheck disable=SC1091
set -a; . ./.env 2>/dev/null; set +a

for v in AI_ARK_API_KEY NOCODB_MCP_TOKEN NOCODB_MCP_URL DISCOVERY_URL N8N_API_KEY; do
  [ -n "${!v:-}" ]
  check "$v is set and non-empty" $?
done

[ "${DISCOVERY_URL:-}" = "https://n8n.lrc-limited.com/webhook/stream" ]
check "DISCOVERY_URL is the production webhook, not webhook-test" $?

# Every endpoint must sit on the live domain. The old host now returns 503, and
# a stale one hides easily: it stays syntactically valid and fails only at runtime.
# git grep, not grep -r: a clone only ever receives TRACKED files, and the
# gitignored Stream Template*.json exports still carry the retired domain.
# The needle is assembled at runtime so this file cannot match itself.
retired="goauto"; retired="${retired}fusion"
! git grep -qI "$retired" -- . 2>/dev/null
check "no tracked file points at the retired domain" $?

case "${NOCODB_MCP_URL:-}" in
  *db.lrc-limited.com/mcp/*) true ;;
  *) false ;;
esac
check "NOCODB_MCP_URL is on the live db host" $?

# .env is the single source of truth; .mcp.json is generated from it by
# setup.sh. If they disagree, setup.sh has not been re-run since .env changed.
python3 - <<'PY'
import json, os, sys
env = {}
for line in open(".env"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        env[k] = v
cfg = json.load(open(".mcp.json"))["mcpServers"]
sys.exit(0 if cfg["nocodb-streams"]["url"] == env.get("NOCODB_MCP_URL") else 1)
PY
check ".mcp.json NocoDB URL matches .env (setup.sh re-run after any .env change)" $?

python3 -c 'import json,sys; json.load(open(".mcp.json"))' 2>/dev/null
check ".mcp.json is valid JSON" $?

python3 - <<'PY' 2>/dev/null
import json, os, sys
c = json.load(open(".mcp.json"))["mcpServers"]
assert set(c) == {"ai-ark", "nocodb-streams"}, c.keys()
assert c["ai-ark"]["type"] == "http"
assert os.environ["AI_ARK_API_KEY"] in c["ai-ark"]["url"]
assert c["nocodb-streams"]["headers"]["xc-mcp-token"] == os.environ["NOCODB_MCP_TOKEN"]
assert c["nocodb-streams"]["url"] == os.environ["NOCODB_MCP_URL"]
PY
check ".mcp.json carries both servers with live credentials" $?

python3 - <<'PY' 2>/dev/null
import os, tomllib
c = tomllib.load(open(".codex/config.toml","rb"))["mcp_servers"]
assert set(c) >= {"ai-ark", "nocodb-streams"}, c.keys()
ark = c["ai-ark"]
assert ark["command"] == "npx"
assert ark["args"][:2] == ["-y", "mcp-remote@0.1.37"]
assert os.environ["AI_ARK_API_KEY"] in ark["args"][2]
assert ark["args"][3:] == ["--transport", "http-only"]
assert ark["startup_timeout_sec"] == 120
assert "url" not in ark
assert c["nocodb-streams"]["http_headers"]["xc-mcp-token"] == os.environ["NOCODB_MCP_TOKEN"]
PY
check ".codex/config.toml bridges AI Ark over STDIO and keeps NocoDB on HTTP" $?

python3 -c 'import json; assert json.load(open(".claude/settings.json"))["enableAllProjectMcpServers"] is True' 2>/dev/null
check ".claude/settings.json auto-approves project MCP servers" $?

grep -q '^.env.example$' .gitignore && exit_bad=1 || exit_bad=0
[ "$exit_bad" -eq 0 ]
check "the .example file is NOT gitignored" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all config checks passed"
