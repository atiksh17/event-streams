#!/usr/bin/env bash
# One-command install for the event-streams skill.
#   ./setup.sh                 full install
#   ./setup.sh --configs-only  regenerate config files, install nothing
set -euo pipefail
cd "$(dirname "$0")"

# Absolute path of this clone. Everything is scoped to it, so the repo works
# from any folder rather than only the one it was first set up in.
REPO_DIR="$(pwd)"

# Credentials live in .env at the repo root - the one place every agent looks.
# credentials.env is the old name, still honoured so an existing checkout does
# not break on upgrade.
if [ -z "${CREDENTIALS_FILE:-}" ]; then
  if   [ -r ./.env ];            then CREDENTIALS_FILE=./.env
  elif [ -r ./credentials.env ]; then CREDENTIALS_FILE=./credentials.env
  else                                CREDENTIALS_FILE=./.env
  fi
fi
CONFIGS_ONLY=0
[ "${1:-}" = "--configs-only" ] && CONFIGS_ONLY=1

say()     { printf '  %s\n' "$*"; }
ok()      { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn()    { printf '  \033[33mskip\033[0m %s\n' "$*"; }
caution() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
die()     { printf '\n  \033[31mfailed\033[0m %s\n\n' "$*" >&2; exit 1; }

# AI Ark's remote endpoint currently violates Streamable HTTP by negotiating
# an event stream and then replying with plain JSON. Codex rejects that
# response, so its project config launches this pinned STDIO bridge instead.
# Pinning keeps a fresh clone reproducible; update only after a live
# initialize + tools/list check against AI Ark.
AI_ARK_BRIDGE_PACKAGE="mcp-remote@0.1.37"

# Codex's rmcp streamable-HTTP client requires an SSE reply. A server that
# answers with anything else kills it with "Transport channel closed" even
# though the server is healthy - Claude Code tolerates the deviation. This
# sends a real (free, unbilled) MCP `initialize` with the Accept header Codex
# sends, and classifies the reply.
#
# $1 = server label, $2 = url, remaining args = extra curl -H flags.
# Sets rc=1 on a genuine failure; sets codex_stream_warned=1 on the SSE quirk.
probe_codex_stream_compat() {
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

# Prove the exact path Codex uses for AI Ark: local STDIO into mcp-remote,
# then the bridge's tolerant HTTP client into AI Ark. The bridge writes its
# remote URL (including the query-string credential) to stderr, so stderr is
# captured and discarded deliberately. Only a credential-free status marker
# comes back to the shell.
probe_codex_ai_ark_bridge() {
  local url="$1" result
  if ! command -v npx >/dev/null 2>&1; then
    printf '  \033[31mFAIL\033[0m codex ai-ark needs Node.js/npm (npx was not found)\n'
    rc=1
    return
  fi

  result=$(python3 - "$url" "$AI_ARK_BRIDGE_PACKAGE" <<'PY'
import json
import select
import subprocess
import sys
import time

url, package = sys.argv[1:3]
request = json.dumps({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "event-streams-setup", "version": "1.0"},
    },
}) + "\n"

process = subprocess.Popen(
    ["npx", "-y", package, url, "--transport", "http-only"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
)
try:
    # Keep stdin open after writing. Codex maintains a long-lived STDIO
    # session; closing it here makes mcp-remote shut down before the remote
    # initialize response can be forwarded.
    process.stdin.write(request)
    process.stdin.flush()
    deadline = time.monotonic() + 120
    outcome = "timeout"
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], deadline - time.monotonic())
        if not ready:
            break
        line = process.stdout.readline()
        if not line:
            outcome = "failed"
            break
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("id") == 1 and "result" in message:
            info = message["result"].get("serverInfo", {})
            outcome = "ok:" + str(info.get("name", "unknown")) + "/" + str(info.get("version", "unknown"))
            break
    print(outcome)
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
PY
)

  case "$result" in
    ok:*) ok "codex ai-ark bridge initialized over STDIO (${result#ok:})" ;;
    timeout)
      printf '  \033[31mFAIL\033[0m codex ai-ark bridge timed out during initialize\n'
      rc=1
      ;;
    *)
      printf '  \033[31mFAIL\033[0m codex ai-ark bridge did not return a valid initialize response\n'
      rc=1
      ;;
  esac
}

# Let the test suite source this file to reach the functions above without
# running an install. Nothing below this line executes when sourced this way.
if [ "${EVENT_STREAMS_SOURCE_ONLY:-}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

echo
echo "event-streams setup"
echo

# ---- 1. credentials -------------------------------------------------------
[ -r "$CREDENTIALS_FILE" ] || die "no credentials file at $CREDENTIALS_FILE. Copy .env.example to .env and fill it in."
set -a; . "$CREDENTIALS_FILE"; set +a

for v in AI_ARK_API_KEY NOCODB_MCP_TOKEN NOCODB_MCP_URL DISCOVERY_URL N8N_API_KEY; do
  [ -n "${!v:-}" ] || die "credential $v is empty in $CREDENTIALS_FILE"
done
ok "credentials loaded (5 values)"

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
command = "npx"
args = ["-y", "${AI_ARK_BRIDGE_PACKAGE}", "${AI_ARK_URL}", "--transport", "http-only"]
startup_timeout_sec = 120

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
#
# Re-verified 2026-08-21, and the gate is the PROJECT TRUST dialog, not the
# settings key. A fresh `git clone` into a path Claude had never seen listed
# both servers as "Pending approval" even though the clone carried
# .claude/settings.json with enableAllProjectMcpServers true. In an already
# trusted folder the same .mcp.json resolves as "Project config (shared via
# .mcp.json)" and connects, with enabledMcpjsonServers still empty. So on a
# new machine the two working routes are: run this script, or open `claude`
# in the folder once and accept the trust prompt. This script exists so the
# first route needs no interactive step.
#
# The cost of this route is drift: these entries are a SNAPSHOT of .env taken
# at setup time, and they SHADOW .mcp.json. On 2026-08-21 the endpoint domain
# moved, .env and .mcp.json were both corrected, and this stale snapshot kept
# pointing every Claude session at the dead host. The verify section below now
# compares the registered URL against .env and fails loudly on a mismatch.
# If you change .env, re-run this script.
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
    # `[ \t]*`, never `\s*`. In Python `\s` matches newlines, so `^\s*trust_level`
    # can start matching at the newline that separates the table header from the
    # key - the replacement then swallows it and emits
    # `[projects."..."]trust_level = "trusted"` on one line. That is invalid TOML
    # and Codex refuses to start at all, machine-wide. Shipped once; do not
    # reintroduce.
    if re.search(r"^[ \t]*trust_level[ \t]*=", section, flags=re.M):
        section = re.sub(r"^[ \t]*trust_level[ \t]*=.*$", 'trust_level = "trusted"',
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

  # Drift guard. The entries installed above are a snapshot of .env, and they
  # shadow .mcp.json, so a stale snapshot silently wins over a corrected repo.
  # "Connected" alone does not prove it is connected to the RIGHT host - on
  # 2026-08-21 a stale entry stayed green against a host that had moved.
  if echo "$out" | grep -q "^nocodb-streams:.*${NOCODB_MCP_URL}"; then
    ok "claude nocodb-streams points at the URL in $CREDENTIALS_FILE"
  else
    printf '  \033[31mFAIL\033[0m claude nocodb-streams does NOT match NOCODB_MCP_URL in %s - stale registration shadowing .mcp.json. Re-run this script.\n' "$CREDENTIALS_FILE"
    rc=1
  fi
  if echo "$out" | grep -q "^ai-ark:.*${AI_ARK_URL}"; then
    ok "claude ai-ark points at the URL derived from $CREDENTIALS_FILE"
  else
    printf '  \033[31mFAIL\033[0m claude ai-ark does NOT match AI_ARK_API_KEY in %s - stale registration. Re-run this script.\n' "$CREDENTIALS_FILE"
    rc=1
  fi

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
  # enabled in config.toml. The probes below exercise the real transports:
  # AI Ark through the local STDIO bridge, and NocoDB through direct
  # Streamable HTTP.
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

  say "codex: probing the AI Ark STDIO bridge and NocoDB Streamable HTTP..."

  probe_codex_ai_ark_bridge "$AI_ARK_URL"
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
