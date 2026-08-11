#!/usr/bin/env bash
# One-command install for the event-streams skill.
#   ./setup.sh                 full install
#   ./setup.sh --configs-only  regenerate config files, install nothing
set -euo pipefail
cd "$(dirname "$0")"

# Absolute path of this clone. Everything is scoped to it, so the repo works
# from any folder rather than only the one it was first set up in.
REPO_DIR="$(pwd)"

CREDENTIALS_FILE="${CREDENTIALS_FILE:-./credentials.env}"
CONFIGS_ONLY=0
[ "${1:-}" = "--configs-only" ] && CONFIGS_ONLY=1

say()     { printf '  %s\n' "$*"; }
ok()      { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn()    { printf '  \033[33mskip\033[0m %s\n' "$*"; }
caution() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
die()     { printf '\n  \033[31mfailed\033[0m %s\n\n' "$*" >&2; exit 1; }

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
# --scope local, NOT --scope user. Local stores the servers under
# projects.<this repo>.mcpServers in the user's own config, so they exist in
# this folder and nowhere else. --scope user would put them in every
# directory on the machine and, worse, would mask a broken project-scoped
# install in every later test.
#
# We deliberately do NOT rely on the repo's own .mcp.json. Claude treats
# repo-supplied MCP config as untrusted and holds it at "Pending approval"
# until a human approves it interactively - verified against
# enableAllProjectMcpServers, enabledMcpjsonServers in settings.json and
# settings.local.json, and a hand-written projects.<path>.enabledMcpjsonServers
# in .claude.json. All four still showed Pending. That gate is deliberate: a
# cloned repo silently gaining live MCP servers would be a supply-chain hole.
# .mcp.json stays in the repo as a fallback for anyone who wants to approve it
# by hand.
if command -v claude >/dev/null 2>&1; then
  # Upgrade path: strip the global entries older versions of this script
  # installed, or they shadow the project-scoped ones and nobody can tell
  # which is actually in play.
  removed_user=0
  for s in ai-ark nocodb-streams; do
    if claude mcp remove "$s" -s user >/dev/null 2>&1; then removed_user=1; fi
  done
  [ "$removed_user" -eq 1 ] && say "removed stale user-scope Claude entries from a previous install"

  for s in ai-ark nocodb-streams; do
    claude mcp remove "$s" -s local >/dev/null 2>&1 || true
  done
  claude mcp add --transport http --scope local ai-ark "$AI_ARK_URL" >/dev/null
  claude mcp add --transport http --scope local nocodb-streams "$NOCODB_MCP_URL" \
    --header "xc-mcp-token: ${NOCODB_MCP_TOKEN}" >/dev/null
  ok "claude: ai-ark + nocodb-streams installed at PROJECT scope ($REPO_DIR)"
else
  warn "claude not on PATH - skipping Claude Code install"
fi

# ---- 5. Codex -------------------------------------------------------------
# The MCP servers live in this repo's own .codex/config.toml (written in step
# 2). Codex ignores that file entirely until the project is trusted, so the
# only thing we write globally is a one-line trust declaration for this path.
# Verified: with an isolated CODEX_HOME and 3 [mcp_servers.*] blocks sitting in
# the project file, `codex mcp list` reported "No MCP servers configured yet"
# until the trust entry existed.
if command -v codex >/dev/null 2>&1; then
  CODEX_CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  mkdir -p "$(dirname "$CODEX_CFG")"; touch "$CODEX_CFG"
  codex_cleanup=$(python3 - "$CODEX_CFG" "$REPO_DIR" <<'PY'
import re, sys
path, repo = sys.argv[1:3]
text = open(path).read()
original = text

# Upgrade path: older versions of this script appended global [mcp_servers.*]
# blocks here. Those shadow the project-scoped ones, so remove them.
text, n_removed = re.subn(
    r"\n?# >>> event-streams >>>.*?# <<< event-streams <<<\n?", "\n", text, flags=re.S)

header = f'[projects."{repo}"]'
if header in text:
    # Section already exists (Codex writes one when a user trusts a repo
    # interactively). Add trust_level inside it only if absent - never append a
    # duplicate table header, which would make the file unparseable.
    start = text.index(header) + len(header)
    nxt = re.search(r"\n\[", text[start:])
    end = start + (nxt.start() if nxt else len(text) - start)
    section = text[start:end]
    if re.search(r"^\s*trust_level\s*=", section, flags=re.M):
        section = re.sub(r"^\s*trust_level\s*=.*$", 'trust_level = "trusted"',
                         section, count=1, flags=re.M)
    else:
        section = '\ntrust_level = "trusted"' + section
    text = text[:start] + section + text[end:]
else:
    text = text.rstrip("\n") + f'\n\n{header}\ntrust_level = "trusted"\n'

if text != original:
    open(path, "w").write(text)
print("removed_global_blocks" if n_removed else "", end="")
PY
)
  [ "$codex_cleanup" = "removed_global_blocks" ] && \
    say "removed stale global Codex [mcp_servers.*] blocks from a previous install"
  ok "codex: project trusted, servers read from this repo's .codex/config.toml"
else
  warn "codex not on PATH - skipping Codex install"
fi

# ---- 6. verify ------------------------------------------------------------
echo
say "verifying..."
rc=0
# A scratch cwd with no project config of its own. Listing the servers from
# here is how we prove they are scoped to this repo rather than installed
# globally - "the server exists somewhere" is precisely the false green this
# whole section exists to prevent.
ELSEWHERE=$(mktemp -d)
trap 'rm -rf "$ELSEWHERE"' EXIT

if command -v claude >/dev/null 2>&1; then
  out=$(claude mcp list 2>&1 || true)
  for s in ai-ark nocodb-streams; do
    if echo "$out" | grep -q "^${s}:.*Connected"; then ok "claude $s connected"
    else printf '  \033[31mFAIL\033[0m claude %s did not connect\n' "$s"; rc=1; fi
  done
  outside=$(cd "$ELSEWHERE" && claude mcp list 2>&1 || true)
  leaked=""
  for s in ai-ark nocodb-streams; do
    if echo "$outside" | grep -q "^${s}:"; then leaked="$leaked $s"; fi
  done
  if [ -n "$leaked" ]; then
    caution "claude:$leaked also resolve OUTSIDE this repo - something is installed at user scope. Project isolation is not holding. Run: claude mcp remove <name> -s user"
  else
    ok "claude scope confirmed: servers resolve here and nowhere else"
  fi
fi
codex_stream_warned=0
if command -v codex >/dev/null 2>&1; then
  # `codex mcp list` only reports registration - is the server present and
  # enabled in config.toml. It says nothing about whether Codex can actually
  # talk to it, which is exactly how AI Ark's incompatibility passed a green
  # install before: registered but unreachable by Codex's client. The probe
  # below is the real connectivity check - it hits each server the way
  # Codex's rmcp streamable-HTTP client would and inspects the response.
  out=$(codex mcp list 2>&1 || true)
  for s in ai-ark nocodb-streams; do
    if echo "$out" | grep -q "$s"; then ok "codex $s registered (config presence only, not a connectivity check)"
    else printf '  \033[31mFAIL\033[0m codex %s missing from config\n' "$s"; rc=1; fi
  done
  outside=$(cd "$ELSEWHERE" && codex mcp list 2>&1 || true)
  leaked=""
  for s in ai-ark nocodb-streams; do
    if echo "$outside" | grep -q "$s"; then leaked="$leaked $s"; fi
  done
  if [ -n "$leaked" ]; then
    caution "codex:$leaked also resolve OUTSIDE this repo - a global [mcp_servers.*] block is present in ${CODEX_HOME:-$HOME/.codex}/config.toml. Project isolation is not holding; remove it."
  else
    ok "codex scope confirmed: servers resolve here and nowhere else"
  fi

  say "codex: probing whether each server actually answers with an SSE stream (what Codex's client requires)..."

  probe_codex_stream_compat() {
    # $1 = server label, $2 = url, remaining args = extra curl -H flags.
    # Sends a real (free, unbilled) MCP `initialize` call with the Accept
    # header Codex sends, then checks the reply's content-type. A server
    # that answers with anything other than text/event-stream will make
    # Codex's rmcp client die with "Transport channel closed" even though
    # the server itself is healthy - Claude Code tolerates the deviation.
    local name="$1" url="$2" hdrs status ctype_line ctype
    shift 2
    hdrs=$(curl -s -D - -o /dev/null -m 15 -X POST "$url" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      "$@" \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"event-streams-setup","version":"1.0"}}}' \
      2>/dev/null) || hdrs=""
    status=$(printf '%s\n' "$hdrs" | awk 'NR==1{print $2}')
    if [ -z "$status" ]; then
      printf '  \033[31mFAIL\033[0m codex %s did not answer the probe at all (connection failed)\n' "$name"
      rc=1
      return
    fi
    # `|| true` is load-bearing: under `set -euo pipefail` a grep that matches
    # nothing exits 1, pipefail propagates it, and the whole script dies here
    # with no output at all. A response with no content-type header is not
    # hypothetical - a bare 502 from a fronting proxy has exactly that shape.
    ctype_line=$(printf '%s\n' "$hdrs" | tr -d '\r' | grep -i '^content-type:' | head -1 || true)
    ctype=$(printf '%s\n' "$ctype_line" | cut -d: -f2- | tr -d ' ' | tr '[:upper:]' '[:lower:]')

    # Status first. A non-2xx is a genuine failure and must not be excused as
    # the known SSE quirk - a wrong NocoDB token also answers with
    # content-type: application/json, and reporting that as "an upstream bug,
    # not a config problem" would send someone hunting the wrong thing.
    case "$status" in
      2*) ;;
      *)
        printf '  \033[31mFAIL\033[0m codex %s answered HTTP %s - that is a real failure, not the SSE quirk. Check the credential and URL for this server.\n' "$name" "$status"
        rc=1
        return
        ;;
    esac

    case "$ctype" in
      text/event-stream*)
        ok "codex $name answers with text/event-stream - Codex's client can use this server"
        ;;
      *)
        caution "codex $name answers HTTP $status with content-type '${ctype:-none}', not text/event-stream. Codex's rmcp client requires an SSE reply and dies with \"Transport channel closed\" against servers that answer this way. Observed for AI Ark on 2026-08-11 and reported as an upstream server bug; retest before assuming it still holds. Claude Code is unaffected. See docs/troubleshooting.md."
        codex_stream_warned=1
        ;;
    esac
  }

  probe_codex_stream_compat "ai-ark" "$AI_ARK_URL"
  probe_codex_stream_compat "nocodb-streams" "$NOCODB_MCP_URL" -H "xc-mcp-token: ${NOCODB_MCP_TOKEN}"
fi

echo
if [ "$rc" -ne 0 ]; then
  die "one or more servers did not come up. See docs/troubleshooting.md"
fi
if [ "$codex_stream_warned" -eq 1 ]; then
  caution "install is otherwise healthy, but at least one server above can't be used from Codex (see the warning). Claude Code is unaffected - use it for anything that needs the affected server. Not treated as a failed install; details in docs/troubleshooting.md."
fi
ok "ready. Open this folder in Claude Code or Codex and say what you want to do."
echo
