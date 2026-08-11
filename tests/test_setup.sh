#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

echo "setup.sh:"

[ -x setup.sh ]
check "setup.sh is executable" $?

bash -n setup.sh 2>/dev/null
check "setup.sh parses" $?

grep -q 'set -euo pipefail' setup.sh
check "setup.sh uses strict mode" $?

# Regeneration is deterministic: running the generator twice must not change bytes.
cp .mcp.json /tmp/mcp.before.$$ && cp .codex/config.toml /tmp/codex.before.$$
./setup.sh --configs-only >/dev/null 2>&1
diff -q /tmp/mcp.before.$$ .mcp.json >/dev/null 2>&1
check "second run leaves .mcp.json byte-identical (idempotent)" $?
diff -q /tmp/codex.before.$$ .codex/config.toml >/dev/null 2>&1
check "second run leaves .codex/config.toml byte-identical (idempotent)" $?
rm -f /tmp/mcp.before.$$ /tmp/codex.before.$$

# Missing credentials must fail loudly, not silently write empty tokens.
out=$(AI_ARK_API_KEY= NOCODB_MCP_TOKEN= bash -c '
  cd "'"$PWD"'"
  CREDENTIALS_FILE=/dev/null ./setup.sh --configs-only 2>&1' ; echo "rc=$?")
echo "$out" | grep -q 'rc=[1-9]'
check "missing credentials exits non-zero" $?
echo "$out" | grep -qi 'credential'
check "missing credentials names the problem" $?

grep -q 'codex mcp add .*nocodb' setup.sh && bad=1 || bad=0
[ "$bad" -eq 0 ]
check "setup.sh does NOT try codex mcp add for nocodb (no --header flag exists)" $?

grep -q 'AI_ARK_BRIDGE_PACKAGE="mcp-remote@0.1.37"' setup.sh
check "AI Ark bridge dependency is pinned for reproducible clones" $?

grep -q 'probe_codex_ai_ark_bridge' setup.sh
check "setup verifies AI Ark through the same STDIO bridge Codex uses" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all setup checks passed"
