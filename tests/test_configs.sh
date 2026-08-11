#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

echo "configs:"

[ -f credentials.env ]
check "credentials.env exists" $?

# shellcheck disable=SC1091
set -a; . ./credentials.env 2>/dev/null; set +a

for v in AI_ARK_API_KEY NOCODB_MCP_TOKEN NOCODB_MCP_URL DISCOVERY_URL; do
  [ -n "${!v:-}" ]
  check "$v is set and non-empty" $?
done

[ "${DISCOVERY_URL:-}" = "https://n8n.goautofusion.com/webhook/stream" ]
check "DISCOVERY_URL is the production webhook, not webhook-test" $?

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
assert os.environ["AI_ARK_API_KEY"] in c["ai-ark"]["url"]
assert c["nocodb-streams"]["http_headers"]["xc-mcp-token"] == os.environ["NOCODB_MCP_TOKEN"]
PY
check ".codex/config.toml uses http_headers for the NocoDB token" $?

python3 -c 'import json; assert json.load(open(".claude/settings.json"))["enableAllProjectMcpServers"] is True' 2>/dev/null
check ".claude/settings.json auto-approves project MCP servers" $?

grep -q '^credentials.env.example$' .gitignore && exit_bad=1 || exit_bad=0
[ "$exit_bad" -eq 0 ]
check "the .example file is NOT gitignored" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all config checks passed"
