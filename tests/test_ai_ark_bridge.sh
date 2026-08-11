#!/usr/bin/env bash
# Unit tests for setup.sh's project-scoped AI Ark STDIO bridge probe.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

EVENT_STREAMS_SOURCE_ONLY=1 . ./setup.sh
set +e

echo "ai-ark bridge:"

type probe_codex_ai_ark_bridge >/dev/null 2>&1
check "bridge probe function is reachable without running an install" $?

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Python's subprocess resolves this fake npx through PATH. It emits a valid
# initialize response and deliberately writes a credential-bearing URL to
# stderr, matching mcp-remote's logging behavior.
cat > "$TMP/npx" <<'SH'
#!/bin/sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"mcp","version":"1.0.0"}}}'
printf '%s\n' 'https://api.ai-ark.com/v1/mcp?token=SHOULD_NOT_ESCAPE' >&2
SH
chmod +x "$TMP/npx"

rc=0
PATH="$TMP:$PATH" probe_codex_ai_ark_bridge "https://api.ai-ark.com/v1/mcp?token=TEST_ONLY" > "$TMP/out" 2>&1
[ "$rc" -eq 0 ] && grep -q 'initialized over STDIO (mcp/1.0.0)' "$TMP/out"
check "valid initialize response passes" $?
grep -q 'SHOULD_NOT_ESCAPE\|TEST_ONLY' "$TMP/out" && leaked=1 || leaked=0
[ "$leaked" -eq 0 ]
check "bridge stderr and credential-bearing URL never reach setup output" $?

cat > "$TMP/npx" <<'SH'
#!/bin/sh
printf '%s\n' 'not an MCP response'
SH
chmod +x "$TMP/npx"

rc=0
PATH="$TMP:$PATH" probe_codex_ai_ark_bridge "https://example.invalid?token=TEST_ONLY" > "$TMP/out" 2>&1
[ "$rc" -eq 1 ] && grep -q 'did not return a valid initialize response' "$TMP/out"
check "invalid initialize response fails clearly" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all ai-ark bridge checks passed"
