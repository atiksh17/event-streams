#!/usr/bin/env bash
# One-command install for the event-streams skill.
#   ./setup.sh                 full install
#   ./setup.sh --configs-only  regenerate config files, install nothing
set -euo pipefail
cd "$(dirname "$0")"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-./credentials.env}"
CONFIGS_ONLY=0
[ "${1:-}" = "--configs-only" ] && CONFIGS_ONLY=1

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mskip\033[0m %s\n' "$*"; }
die()  { printf '\n  \033[31mfailed\033[0m %s\n\n' "$*" >&2; exit 1; }

echo
echo "event-streams setup"
echo

# ---- 1. credentials -------------------------------------------------------
[ -r "$CREDENTIALS_FILE" ] || die "no credentials file at $CREDENTIALS_FILE. Copy credentials.env.example to credentials.env and fill it in."
set -a; . "$CREDENTIALS_FILE"; set +a

for v in AI_ARK_API_KEY NOCODB_MCP_TOKEN NOCODB_MCP_URL DISCOVERY_URL; do
  [ -n "${!v:-}" ] || die "credential $v is empty in $CREDENTIALS_FILE"
done
ok "credentials loaded (4 values)"

# ---- 2. generate configs --------------------------------------------------
AI_ARK_URL="https://api.ai-ark.com/v1/mcp?token=${AI_ARK_API_KEY}"

cat > .mcp.json <<JSON
{
  "mcpServers": {
    "ai-ark": {
      "type": "http",
      "url": "${AI_ARK_URL}"
    },
    "nocodb-streams": {
      "type": "http",
      "url": "${NOCODB_MCP_URL}",
      "headers": {
        "xc-mcp-token": "${NOCODB_MCP_TOKEN}"
      }
    }
  }
}
JSON
ok "wrote .mcp.json"

mkdir -p .codex
cat > .codex/config.toml <<TOML
# Codex project-local MCP wiring.
# codex mcp add exposes only --bearer-token-env-var, so NocoDB's custom
# xc-mcp-token header cannot be set from the CLI. http_headers is the only
# route. Do not "simplify" this to a codex mcp add call.

[mcp_servers.ai-ark]
url = "${AI_ARK_URL}"

[mcp_servers.nocodb-streams]
url = "${NOCODB_MCP_URL}"

[mcp_servers.nocodb-streams.http_headers]
"xc-mcp-token" = "${NOCODB_MCP_TOKEN}"
TOML
ok "wrote .codex/config.toml"

mkdir -p data
[ -f data/.gitkeep ] || touch data/.gitkeep

if [ "$CONFIGS_ONLY" -eq 1 ]; then echo; ok "configs regenerated"; echo; exit 0; fi

# ---- 3. skill layout ------------------------------------------------------
[ -f .claude/skills/event-streams/SKILL.md ] || die "canonical skill missing at .claude/skills/event-streams/SKILL.md"
if [ -L .codex/skills/event-streams ]; then
  ok "skill symlink intact"
elif [ -e .codex/skills/event-streams ]; then
  die ".codex/skills/event-streams is a real file, not a symlink. On Windows run: git config --global core.symlinks true, then re-clone."
else
  mkdir -p .codex/skills
  ln -s ../../.claude/skills/event-streams .codex/skills/event-streams
  ok "created skill symlink"
fi

# ---- 4. Claude Code -------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  claude mcp remove ai-ark        -s user >/dev/null 2>&1 || true
  claude mcp remove nocodb-streams -s user >/dev/null 2>&1 || true
  claude mcp add --transport http --scope user ai-ark "$AI_ARK_URL" >/dev/null
  claude mcp add --transport http --scope user nocodb-streams "$NOCODB_MCP_URL" \
    --header "xc-mcp-token: ${NOCODB_MCP_TOKEN}" >/dev/null
  ok "claude: ai-ark + nocodb-streams installed at user scope"
else
  warn "claude not on PATH - skipping Claude Code install"
fi

# ---- 5. Codex -------------------------------------------------------------
if command -v codex >/dev/null 2>&1; then
  CODEX_CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  mkdir -p "$(dirname "$CODEX_CFG")"; touch "$CODEX_CFG"
  python3 - "$CODEX_CFG" "$AI_ARK_URL" "$NOCODB_MCP_URL" "$NOCODB_MCP_TOKEN" <<'PY'
import re, sys
path, ark, nocodb_url, nocodb_tok = sys.argv[1:5]
text = open(path).read()
# Drop any previous blocks we own, then append fresh ones. Idempotent.
text = re.sub(r"\n?# >>> event-streams >>>.*?# <<< event-streams <<<\n?", "\n", text, flags=re.S)
block = f'''
# >>> event-streams >>>
[mcp_servers.ai-ark]
url = "{ark}"

[mcp_servers.nocodb-streams]
url = "{nocodb_url}"

[mcp_servers.nocodb-streams.http_headers]
"xc-mcp-token" = "{nocodb_tok}"
# <<< event-streams <<<
'''
open(path, "w").write(text.rstrip("\n") + "\n" + block)
PY
  ok "codex: ai-ark + nocodb-streams written to $CODEX_CFG"
else
  warn "codex not on PATH - skipping Codex install"
fi

# ---- 6. verify ------------------------------------------------------------
echo
say "verifying..."
rc=0
if command -v claude >/dev/null 2>&1; then
  out=$(claude mcp list 2>&1 || true)
  for s in ai-ark nocodb-streams; do
    if echo "$out" | grep -q "^${s}:.*Connected"; then ok "claude $s connected"
    else printf '  \033[31mFAIL\033[0m claude %s did not connect\n' "$s"; rc=1; fi
  done
fi
if command -v codex >/dev/null 2>&1; then
  out=$(codex mcp list 2>&1 || true)
  for s in ai-ark nocodb-streams; do
    if echo "$out" | grep -q "$s"; then ok "codex $s registered"
    else printf '  \033[31mFAIL\033[0m codex %s missing\n' "$s"; rc=1; fi
  done
fi

echo
if [ "$rc" -ne 0 ]; then
  die "one or more servers did not come up. See docs/troubleshooting.md"
fi
ok "ready. Open this folder in Claude Code or Codex and say what you want to do."
echo
