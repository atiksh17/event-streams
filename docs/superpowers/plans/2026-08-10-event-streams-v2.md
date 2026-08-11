# event-streams v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a private GitHub repo that a non-technical person clones and runs one command against, giving both Claude Code and Codex a two-mode lead-sourcing skill backed by two MCP servers and no scripts of its own.

**Architecture:** A markdown skill stored once at `.claude/skills/event-streams/SKILL.md` and symlinked into `.codex/skills/`. Test mode POSTs to an n8n webhook and iterates on keywords/prompt. Production mode reads NocoDB rows, enriches via AI Ark, and writes a CSV. `setup.sh` generates both harnesses' MCP configs from one credentials file and installs them at user scope.

**Tech Stack:** Markdown, JSON, TOML, bash. No Python, no Node, no package manager. Tests are bash scripts run directly.

## Global Constraints

- **No skill-owned scripts.** `setup.sh` and `tests/*.sh` are repo infrastructure and run at install or in CI. The skill itself issues only `curl` and MCP tool calls.
- **Production mode never writes to NocoDB.** Only `getBaseInfo`, `getTablesList`, `getTableSchema`, `queryRecords`, `getRecord`, `countRecords`, `aggregate`, `readAttachment` are permitted. `createRecords`, `updateRecords`, `deleteRecords` are forbidden.
- **Test mode never touches NocoDB. Production mode never touches the discovery endpoint.**
- **Discovery production URL:** `https://n8n.goautofusion.com/webhook/stream`. The `webhook-test/stream` variant is documentation-only.
- **Discovery request body:** `{"keywords": "<comma separated>", "qualificationPrompt": "<text>"}`
- **A discovery run takes 5–15 minutes.** Claude Code's Bash tool caps a foreground command at 600000 ms. Every discovery call is backgrounded to a file and polled. Never a blocking foreground `curl`.
- **Job titles are requested from the user before every enrichment run**, with no exceptions and no carry-over between runs in the same conversation.
- **`Streams` and `Template` are reserved tables.** Never enrichment targets. `Template` is never read or written.
- **Real API keys are committed.** The repo is private; this is the user's stated decision. Keys live in `credentials.env` as the single source of truth.
- **NocoDB MCP endpoint:** `https://db.goautofusion.com/mcp/nc6gt1uozqt6i76m`, header `xc-mcp-token`.
- **AI Ark MCP endpoint:** `https://api.ai-ark.com/v1/mcp?token=<key>` — token is a query parameter, not a header.
- **Repo lives on branch `build`** until the final task renames it to `main`.

---

### Task 1: Repo skeleton, canonical skill, and the layout test

Establishes the two-path skill layout that everything else depends on. The symlink is the load-bearing piece: it is what makes one file serve both harnesses.

**Files:**
- Create: `.claude/skills/event-streams/SKILL.md`
- Create: `.codex/skills/event-streams` (symlink)
- Create: `data/.gitkeep`
- Create: `tests/test_layout.sh`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: the skill path `.claude/skills/event-streams/SKILL.md`, which Tasks 5–7 write into. `tests/test_layout.sh` is extended by Task 3.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_layout.sh
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() {  # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi
}

echo "layout:"

[ -f .claude/skills/event-streams/SKILL.md ]
check "canonical SKILL.md exists" $?

[ -L .codex/skills/event-streams ]
check ".codex/skills/event-streams is a symlink (not a copy)" $?

[ -f .codex/skills/event-streams/SKILL.md ]
check "symlink resolves to a readable SKILL.md" $?

a=$(cat .claude/skills/event-streams/SKILL.md 2>/dev/null | shasum | cut -d' ' -f1)
b=$(cat .codex/skills/event-streams/SKILL.md 2>/dev/null | shasum | cut -d' ' -f1)
[ -n "$a" ] && [ "$a" = "$b" ]
check "both paths serve identical bytes" $?

head -1 .claude/skills/event-streams/SKILL.md | grep -q '^---$'
check "SKILL.md starts with YAML frontmatter" $?

grep -q '^name: event-streams$' .claude/skills/event-streams/SKILL.md
check "frontmatter declares name: event-streams" $?

[ -d data ]
check "data/ exists" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all layout checks passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/test_layout.sh && ./tests/test_layout.sh`
Expected: FAIL — `canonical SKILL.md exists` and every check after it fail, exit 1.

- [ ] **Step 3: Create the skill file and symlink**

```bash
mkdir -p .claude/skills/event-streams .codex/skills data
touch data/.gitkeep
```

Write `.claude/skills/event-streams/SKILL.md` with frontmatter and section stubs only. Tasks 5 and 6 fill the bodies.

```markdown
---
name: event-streams
description: Use when trialling keywords and qualification prompts for a lead-sourcing stream ("test these keywords", "the results are too broad", "try a tighter prompt"), or when turning rows an automated stream has already collected into an enriched contact CSV ("enrich the new rows in <table>", "get me contacts for these companies"). Two modes, one endpoint each, no scripts.
---

# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

Two modes. They share no systems, and picking the wrong one wastes either
fifteen minutes or real money.

| Mode | Use when | Touches |
|---|---|---|
| **Test** | Trialling keywords and a qualification prompt | Discovery endpoint only |
| **Production** | Enriching rows a daily stream already collected | NocoDB + AI Ark only |

Test mode never reads NocoDB. Production mode never calls the discovery
endpoint.

## Test mode

<!-- Task 5 -->

## Production mode

<!-- Task 6 -->

## Rules that must not need a lookup

<!-- Task 6 -->
```

Then create the symlink with a **relative** target, so it survives being cloned anywhere:

```bash
ln -s ../../.claude/skills/event-streams .codex/skills/event-streams
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/test_layout.sh`
Expected: PASS — `all layout checks passed`, exit 0.

- [ ] **Step 5: Verify the symlink is stored as a symlink in git, not a copy**

```bash
git add -A
git ls-files -s .codex/skills/event-streams
```

Expected: mode `120000` (symlink). If it shows `100644`, git stored a regular file — the clone would carry a duplicate that silently drifts. Fix with `git config core.symlinks true` and re-add.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: skill layout with shared canonical SKILL.md

.codex/skills/event-streams is a relative symlink to the .claude copy.
Verified stored as git mode 120000, so clones get a link not a duplicate.
Both harnesses' project-local skill discovery was confirmed empirically."
```

---

### Task 2: Credentials file and generated MCP configs

One credentials file feeds three generated configs. Rotating a key means editing one line and re-running setup.

**Files:**
- Create: `credentials.env`
- Create: `credentials.env.example`
- Create: `.mcp.json`
- Create: `.codex/config.toml`
- Create: `.claude/settings.json`
- Create: `tests/test_configs.sh`

**Interfaces:**
- Consumes: nothing from Task 1
- Produces: `credentials.env` defining `AI_ARK_API_KEY`, `NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL`. Task 3's `setup.sh` sources this file and regenerates `.mcp.json` and `.codex/config.toml` from it.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_configs.sh
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/test_configs.sh && ./tests/test_configs.sh`
Expected: FAIL — `credentials.env exists` fails, and every dependent check fails, exit 1.

- [ ] **Step 3: Create `credentials.env.example`**

```bash
# credentials.env.example
# Copy to credentials.env and fill in. In this private repo the real
# credentials.env IS committed - it is the single source of truth for
# every generated config. Change a value here, re-run ./setup.sh, commit.

# AI Ark: https://app.ai-ark.com/settings/api-management/dashboard
AI_ARK_API_KEY=

# NocoDB: base > Overview > Settings > Model Context Protocol > New MCP Endpoint
# Use a READ-ONLY token. Production mode never writes, and deleteRecords
# hits the live base with no undo.
NOCODB_MCP_TOKEN=
NOCODB_MCP_URL=https://db.goautofusion.com/mcp/nc6gt1uozqt6i76m

# n8n discovery webhook - production URL, never webhook-test
DISCOVERY_URL=https://n8n.goautofusion.com/webhook/stream
```

- [ ] **Step 4: Create `credentials.env` with the real values**

Copy the example and fill in the two secrets. Obtain them from the user's
existing `.env` at `~/Documents/Cycling event scraper/.env` **without printing
them to the terminal**:

```bash
cp credentials.env.example credentials.env
# then, without echoing values:
python3 - <<'PY'
import re, pathlib
src = pathlib.Path.home() / "Documents/Cycling event scraper/.env"
env = dict(
    re.match(r"([A-Za-z_][A-Za-z0-9_]*)=(.*)", ln).groups()
    for ln in src.read_text().splitlines()
    if re.match(r"[A-Za-z_][A-Za-z0-9_]*=", ln)
)
dst = pathlib.Path("credentials.env")
out = dst.read_text().replace("AI_ARK_API_KEY=", f"AI_ARK_API_KEY={env.get('AI_ARK', '')}")
dst.write_text(out)
print("AI_ARK_API_KEY written:", bool(env.get("AI_ARK")))
PY
```

`NOCODB_MCP_TOKEN` is not in that `.env`. Ask the user to paste it into
`credentials.env` directly, or to regenerate one in the NocoDB UI. Do not ask
them to paste it into the conversation.

- [ ] **Step 5: Create `.claude/settings.json`**

```json
{
  "enableAllProjectMcpServers": true
}
```

- [ ] **Step 6: Generate `.mcp.json` and `.codex/config.toml`**

These are generated by `setup.sh` in Task 3, but write them by hand now so the
test can pass and the shape is fixed before the generator is written.

`.mcp.json`:

```json
{
  "mcpServers": {
    "ai-ark": {
      "type": "http",
      "url": "https://api.ai-ark.com/v1/mcp?token=<AI_ARK_API_KEY>"
    },
    "nocodb-streams": {
      "type": "http",
      "url": "https://db.goautofusion.com/mcp/nc6gt1uozqt6i76m",
      "headers": {
        "xc-mcp-token": "<NOCODB_MCP_TOKEN>"
      }
    }
  }
}
```

`.codex/config.toml` — note `http_headers`, which `codex mcp add` cannot reach:

```toml
# Codex project-local MCP wiring.
# codex mcp add exposes only --bearer-token-env-var, so NocoDB's custom
# xc-mcp-token header cannot be set from the CLI. http_headers is the only
# route. Do not "simplify" this to a codex mcp add call.

[mcp_servers.ai-ark]
url = "https://api.ai-ark.com/v1/mcp?token=<AI_ARK_API_KEY>"

[mcp_servers.nocodb-streams]
url = "https://db.goautofusion.com/mcp/nc6gt1uozqt6i76m"

[mcp_servers.nocodb-streams.http_headers]
"xc-mcp-token" = "<NOCODB_MCP_TOKEN>"
```

Substitute the real values from `credentials.env` for the two placeholders.

- [ ] **Step 7: Remove `.env` from `.gitignore` and confirm credentials commit**

`.gitignore` currently ignores `.env`. `credentials.env` is a different filename
and is intentionally tracked. Verify:

```bash
git check-ignore -v credentials.env || echo "credentials.env is tracked - correct"
```

Expected: `credentials.env is tracked - correct`.

- [ ] **Step 8: Run test to verify it passes**

Run: `./tests/test_configs.sh`
Expected: PASS — `all config checks passed`, exit 0.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: credentials file and generated MCP configs

credentials.env is the single source of truth; .mcp.json and
.codex/config.toml are generated from it. Codex needs http_headers
because codex mcp add has no --header flag - NocoDB is unreachable
from the Codex CLI without it."
```

---

### Task 3: setup.sh

The one command. Must be idempotent, must skip a missing harness rather than fail, and must exit non-zero when a server does not answer — a half-configured install fails later, looking like a different problem.

**Files:**
- Create: `setup.sh`
- Create: `tests/test_setup.sh`
- Modify: `tests/test_layout.sh` (add the executable-bit check)

**Interfaces:**
- Consumes: `credentials.env` from Task 2 (`AI_ARK_API_KEY`, `NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL`)
- Produces: `./setup.sh`, referenced by the README in Task 8 and by the clean-clone verification in Task 10.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_setup.sh
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

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all setup checks passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/test_setup.sh && ./tests/test_setup.sh`
Expected: FAIL — `setup.sh is executable` fails first, exit 1.

- [ ] **Step 3: Write setup.sh**

```bash
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
# Generated by setup.sh from credentials.env. Edit credentials.env, not this.
#
# codex mcp add exposes only --bearer-token-env-var, so NocoDB's custom
# xc-mcp-token header cannot be set from the CLI. http_headers is the only
# route by which NocoDB reaches Codex. Do not replace this with codex mcp add.

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x setup.sh && ./tests/test_setup.sh`
Expected: PASS — `all setup checks passed`, exit 0.

- [ ] **Step 5: Run the real thing and confirm both servers connect**

Run: `./setup.sh`
Expected: `ok claude ai-ark connected`, `ok claude nocodb-streams connected`, `ok codex ... registered`, then `ready.` and exit 0.

If a server fails here, stop and fix it before continuing — Task 4 depends on
the AI Ark server actually answering.

- [ ] **Step 6: Run it a second time**

Run: `./setup.sh && ./tests/test_setup.sh`
Expected: identical output, no duplicated blocks in `~/.codex/config.toml`
(`grep -c 'event-streams >>>' ~/.codex/config.toml` returns `1`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: one-command setup.sh

Idempotent, skips a missing harness rather than failing, exits non-zero
when a server does not answer. Codex config is merged via a marked block
so re-running replaces rather than appends."
```

---

### Task 4: Enumerate the real MCP tool surfaces

The skill cannot name tools it has not seen. AI Ark's documentation lists no tool names at all. This task exists because the last project lost a day to assumed field names.

**Files:**
- Create: `docs/reference/endpoints.md`

**Interfaces:**
- Consumes: MCP servers installed by Task 3
- Produces: exact tool names and argument shapes, quoted verbatim in `docs/reference/endpoints.md`. Tasks 5 and 6 write those names into `SKILL.md` and must copy them from this file, never from memory.

- [ ] **Step 1: List AI Ark's tools from the live server**

Restart the agent session so the new MCP servers load, then call the AI Ark
server's tool list. Record every tool name, its description, and its required
arguments.

If the harness offers no direct listing, probe over HTTP:

```bash
set -a; . ./credentials.env; set +a
curl -sS -X POST "https://api.ai-ark.com/v1/mcp?token=${AI_ARK_API_KEY}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
       "protocolVersion":"2025-06-18","capabilities":{},
       "clientInfo":{"name":"probe","version":"1"}}}'
```

then repeat with `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}`.

- [ ] **Step 2: Confirm NocoDB's tools and the reserved table names**

```bash
set -a; . ./credentials.env; set +a
curl -sS -X POST "${NOCODB_MCP_URL}" \
  -H "xc-mcp-token: ${NOCODB_MCP_TOKEN}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

Expected 11 tools: `getBaseInfo`, `getTablesList`, `getTableSchema`,
`queryRecords`, `getRecord`, `countRecords`, `readAttachment`, `aggregate`,
`createRecords`, `updateRecords`, `deleteRecords`.

Then call `getTablesList` and record the **real** table names, so the skill can
name `Streams` and `Template` exactly as they appear rather than approximately.

- [ ] **Step 3: Verify the NocoDB token is read-only**

```bash
curl -sS -X POST "${NOCODB_MCP_URL}" \
  -H "xc-mcp-token: ${NOCODB_MCP_TOKEN}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
       "name":"createRecords","arguments":{"tableName":"Template","records":[]}}}'
```

Expected: a permission error from the server.

If it succeeds, the token has write access. Report this to the user and ask them
to issue a read-only token before continuing — the restriction has to be
enforced at the token, not by hoping the agent behaves. Record the outcome
either way; do not quietly proceed with a write-capable token.

- [ ] **Step 4: Write `docs/reference/endpoints.md`**

Record, with every value copied from the probe output rather than from this
plan: the discovery endpoint URL, method, request body, and one real response;
both MCP server URLs and auth mechanisms; the full AI Ark tool list with
arguments; the NocoDB tool list split into permitted and forbidden; the real
reserved table names; and the read-only verification result from Step 3.

- [ ] **Step 5: Commit**

```bash
git add docs/reference/endpoints.md
git commit -m "docs: real MCP tool surfaces, probed not assumed

AI Ark's docs list no tool names. Every name here came from tools/list
against the live servers. Includes the read-only token verification."
```

---

### Task 5: Test mode

**Files:**
- Modify: `.claude/skills/event-streams/SKILL.md` (the `## Test mode` section)
- Create: `docs/test-mode.md`

**Interfaces:**
- Consumes: `DISCOVERY_URL` from Task 2; the response shape recorded in Task 4
- Produces: the test-mode procedure. Task 8's README links to `docs/test-mode.md`.

- [ ] **Step 1: Write the `## Test mode` section of SKILL.md**

```markdown
## Test mode

Trialling keywords and a qualification prompt. Touches the discovery endpoint
and nothing else — no NocoDB, no AI Ark, nothing is spent.

### Before you start, say this out loud

> This takes 5 to 15 minutes. I'll tell you the moment it lands.

A silent ten-minute wait reads as a crash.

### Fire the request

**Never run this in the foreground.** A discovery run can take 15 minutes and
the agent harness kills a foreground command at 10. The kill looks exactly like
a dead endpoint, and you will debug the wrong thing.

    mkdir -p data/.runs
    RUN=$(date +%Y%m%d-%H%M%S)
    cat > "data/.runs/$RUN.request.json" <<'JSON'
    {"keywords": "...", "qualificationPrompt": "..."}
    JSON
    nohup curl -sS --max-time 1800 -X POST https://n8n.goautofusion.com/webhook/stream \
      -H 'Content-Type: application/json' \
      -d @"data/.runs/$RUN.request.json" \
      -o "data/.runs/$RUN.response.json" \
      -w '%{http_code}' > "data/.runs/$RUN.status" 2>&1 &

Then poll for `data/.runs/$RUN.status`. When it appears, the run is done and the
file holds the HTTP status.

Use `https://n8n.goautofusion.com/webhook/stream`. The `webhook-test/` variant
is single-shot and only works right after someone clicks *Execute workflow* in
n8n — it is a debugging aid, never the skill's path.

### Show the results

One row per company. `content` is long — show it only when asked.

| Company | Relevant | Confidence | Why |
|---|---|---|---|

Then state the pass rate plainly: *"14 of 61 passed."*

### Iterate

Ask what is wrong with it, specifically. "Too broad" is a start, not an answer —
push for which companies should not be there and why. Then rewrite the
qualification prompt, **show the before and after**, and re-run only once the
user agrees.

Every re-run costs another 5–15 minutes, so it is worth one more question up
front rather than three more runs.

### When the user is happy

Print the row for them to add to the `Streams` table:

    keywords:            <the winning keywords>
    qualificationPrompt: <the winning prompt>

**You do not write this row.** A row in `Streams` means "run this every day,
forever" — that is the user's decision to make in NocoDB, not a side effect of
a successful test.

### When it goes wrong

| What you see | What it means | What to say |
|---|---|---|
| `404 ... webhook "stream" is not registered` | The test URL was used | Use the production URL |
| `{"message":"Workflow was started"}` | n8n is set to respond immediately | The workflow needs a *Respond to Webhook* node; results are not coming |
| `[]` | Keywords matched nothing | A keyword problem, not a fault |
| Every row `relevant: false` | Prompt too strict | A prompt problem — offer a looser rewrite |
| Body is not JSON | n8n returned an error page | Show the first 500 bytes, do not parse |
| `.status` never appears | Run exceeded 30 minutes | Report the timeout. Do not silently retry |
```

- [ ] **Step 2: Verify the section against the spec**

Run: `grep -c 'webhook-test' .claude/skills/event-streams/SKILL.md`
Expected: `1` — mentioned once, as the thing not to use.

Run: `grep -q 'nohup' .claude/skills/event-streams/SKILL.md && echo backgrounded`
Expected: `backgrounded`.

- [ ] **Step 3: Write `docs/test-mode.md`**

The long-form companion: how to write a qualification prompt that discriminates,
worked before/after examples of tightening one, what a healthy pass rate looks
like, and why a low pass rate is usually correct behaviour rather than a fault.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: test mode

Backgrounded curl because a 15-minute call exceeds the harness's 10-minute
foreground cap. Skill prints the Streams row rather than writing it - a
test should not be able to create a permanent daily job."
```

---

### Task 6: Production mode

**Files:**
- Modify: `.claude/skills/event-streams/SKILL.md` (`## Production mode` and `## Rules`)
- Create: `docs/production-mode.md`

**Interfaces:**
- Consumes: NocoDB and AI Ark tool names from `docs/reference/endpoints.md` (Task 4)
- Produces: the production procedure and the CSV column list, used by Task 11's live run.

- [ ] **Step 1: Write the `## Production mode` section of SKILL.md**

Replace every `<tool>` below with the real name from
`docs/reference/endpoints.md`. Do not write a tool name from memory.

```markdown
## Production mode

The daily stream has already done discovery and judging. You start from its
rows. You never call the discovery endpoint here.

### 1. Find out what to enrich

Ask which table, and which rows. The user can see the base and you cannot —
their answer is authoritative. "The new ones" is a valid answer; ask them which
ones those are.

`Streams` and `Template` are never enrichment targets. `Streams` is the
scheduler — read it to list what is running. `Template` is marked *do not
delete*; never read it, never write it, never offer it.

### 2. Read the rows

Read-only, always: `getTablesList`, `getTableSchema`, `queryRecords`,
`getRecord`, `countRecords`, `aggregate`.

**Never** `createRecords`, `updateRecords`, or `deleteRecords`. Nothing in this
mode writes to NocoDB. If you believe you need to write, you have misread the
task — stop and ask.

### 3. Ask for the job titles

**Every run. Before anything is spent. No exceptions.**

> Which job titles do you want at these companies?

If an earlier run in this same conversation used titles, you may *offer* them —
"last time you used Head of HR, People Director, CSR Manager — same again?" —
but the user must say yes. Never carry them over silently, and never infer them
from the table.

### 4. Confirm the spend

State it plainly and wait:

> 38 companies × 3 job titles. Enriching now?

### 5. Enrich

One company at a time via AI Ark. **Isolate failures** — a company that returns
nothing must not abort the batch. Record why each empty one was empty; the
reasons are the most useful part of the report when coverage is poor.

### 6. Write the CSV

`data/<table-slug>-YYYY-MM-DD.csv`, unless the user has said they want
something else — in which case theirs wins and you do not argue.

Columns: `company`, `person_name`, `job_title`, `email`, `linkedin_url`,
`source_table`, `enriched_at`. One row per person. Companies that returned
nobody appear in the report, not as blank rows.

### 7. Report honestly

    38 companies in
    91 people out
    64 with an email (70%)
    88 with a LinkedIn (97%)
    6 companies returned nobody

If coverage is poor, say so and say why. Do not round it up and do not present
a thin result as a good one.

## Rules that must not need a lookup

**1. Never print a secret.** Not a key, not a token. They live in
`credentials.env`. To check one, print whether it is set and how long it is —
never its value.

**2. Job titles are asked for every single time.** It is the one question that
stands between the user and money they did not mean to spend.

**3. Nothing in production mode writes to NocoDB.** The base is the automated
system's, not yours.

**4. Test mode and production mode share nothing.** If you are reaching for
NocoDB in test mode or the discovery endpoint in production mode, you are in
the wrong mode.
```

- [ ] **Step 2: Verify no forbidden tool is referenced as usable**

Run:

```bash
grep -n 'createRecords\|updateRecords\|deleteRecords' .claude/skills/event-streams/SKILL.md
```

Expected: matches appear only on the "Never" line. Any other occurrence is a bug.

- [ ] **Step 3: Write `docs/production-mode.md`**

The long-form companion: choosing job titles that actually return people,
reading the coverage report, what to do when a company returns nobody, and why
the CSV is the deliverable rather than a NocoDB write.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: production mode

Read-only against NocoDB. Job titles requested before every run with no
carry-over. Reserved tables named explicitly."
```

---

### Task 7: Docs, router files, and the link check

**Files:**
- Create: `docs/INDEX.md`, `docs/troubleshooting.md`, `README.md`, `CLAUDE.md`, `AGENTS.md`
- Create: `tests/test_docs.sh`

**Interfaces:**
- Consumes: every doc file created in Tasks 4–6
- Produces: `tests/test_docs.sh`, run by Task 9's full suite.

- [ ] **Step 1: Write the failing test**

```bash
# tests/test_docs.sh
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

echo "docs:"

for f in README.md CLAUDE.md AGENTS.md docs/INDEX.md docs/test-mode.md \
         docs/production-mode.md docs/troubleshooting.md docs/reference/endpoints.md; do
  [ -f "$f" ]; check "$f exists" $?
done

diff -q CLAUDE.md AGENTS.md >/dev/null 2>&1
check "CLAUDE.md and AGENTS.md are identical" $?

# every relative markdown link resolves
broken=0
while IFS= read -r line; do
  f="${line%%:*}"; link="${line#*:}"
  case "$link" in http*|\#*) continue;; esac
  target="$(dirname "$f")/${link%%#*}"
  [ -e "$target" ] || { echo "     broken: $f -> $link"; broken=1; }
done < <(grep -roE '\]\([^)]+\)' --include='*.md' . \
         | grep -v '/superpowers/' \
         | sed -E 's/\]\(/:/; s/\)$//')
[ "$broken" -eq 0 ]
check "every relative markdown link resolves" $?

grep -q 'webhook/stream' README.md || grep -q 'setup.sh' README.md
check "README names the install command" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all doc checks passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/test_docs.sh && ./tests/test_docs.sh`
Expected: FAIL — the missing files are listed, exit 1.

- [ ] **Step 3: Write `README.md`**

Front door for someone non-technical. Must contain, in this order: one sentence
on what this does; the install block; and a paste-block they hand to their
agent.

````markdown
# Event Streams

Finds companies whose staff are doing organised events, and finds the senior
people to contact at them.

## Install

```bash
git clone https://github.com/atiksh17/<repo>.git
cd <repo>
./setup.sh
```

That is the whole install. Open the folder in Claude Code or Codex afterwards
and just say what you want.

## What to say to your agent

Copy this:

> I want to use the event-streams skill in this folder.
> Test some keywords for me first, then we'll enrich.

## The two modes

**Testing keywords** — you give keywords and a description of what counts as a
good result. It goes and looks, then shows you what it found so you can sharpen
the description. Takes 5 to 15 minutes each time.

**Enriching** — the system collects results every day on its own. When you want
contacts, name the table and it produces a spreadsheet of people with emails and
LinkedIn profiles.

Full detail in [docs/INDEX.md](docs/INDEX.md).

## If something breaks

[docs/troubleshooting.md](docs/troubleshooting.md).
````

- [ ] **Step 4: Write `CLAUDE.md`, then copy it to `AGENTS.md`**

Addressed to the agent. Points at `docs/INDEX.md`, states the four rules from
Task 6, and names the mode split. Then:

```bash
cp CLAUDE.md AGENTS.md
```

- [ ] **Step 5: Write `docs/INDEX.md` and `docs/troubleshooting.md`**

`INDEX.md` maps every doc with a "read this when…" line.
`troubleshooting.md` merges both failure tables from Tasks 5 and 6, plus the
install failures: `claude`/`codex` not on PATH, symlink stored as a real file on
Windows, MCP server not connecting after setup, and a write-capable NocoDB token.

- [ ] **Step 6: Run test to verify it passes**

Run: `./tests/test_docs.sh`
Expected: PASS — `all doc checks passed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: README, router mirrors, index, troubleshooting

CLAUDE.md and AGENTS.md are byte-identical and enforced by a test.
Link checker skips docs/superpowers/ - plan files quote paths as
examples, not as links."
```

---

### Task 8: Full suite, clean-clone verification, and push

Nothing here is real until it works from a fresh clone. Both bugs that escaped the last project's unit tests were found exactly this way.

**Files:**
- Create: `tests/run_all.sh`
- Modify: `README.md` (replace `<repo>` with the real name)

**Interfaces:**
- Consumes: every test from Tasks 1, 2, 3, 7
- Produces: a pushed private repo

- [ ] **Step 1: Write the runner**

```bash
# tests/run_all.sh
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/test_layout.sh tests/test_configs.sh tests/test_setup.sh tests/test_docs.sh; do
  echo; bash "$t" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "SUITE PASSED" || echo "SUITE FAILED"
exit "$rc"
```

- [ ] **Step 2: Run it**

Run: `chmod +x tests/run_all.sh && ./tests/run_all.sh`
Expected: `SUITE PASSED`, exit 0.

- [ ] **Step 3: Verify the skill loads from a clean clone in both harnesses**

```bash
SCRATCH=$(mktemp -d)
git clone --local . "$SCRATCH/event-streams"
cd "$SCRATCH/event-streams"
ls -la .codex/skills/event-streams          # must be a symlink
cat .codex/skills/event-streams/SKILL.md | head -3
codex exec --sandbox read-only "List the names of every skill available to you, one per line. No tools."
```

Expected: `.codex/skills/event-streams` is a symlink, and `event-streams`
appears in the Codex skill list.

For Claude Code, open the scratch clone and confirm the skill is offered.

- [ ] **Step 4: Run the full suite inside the clean clone**

Run: `./tests/run_all.sh`
Expected: `SUITE PASSED`. A pass here and a fail in the working copy (or the
reverse) means something is untracked — find it before pushing.

- [ ] **Step 5: Create the private repo and push**

```bash
cd /Users/atiksh/Documents/event-streams
git branch -M main          # a rename is not a commit, so the main-branch guard hook allows it
gh repo create atiksh17/<repo> --private --source=. --remote=origin --push
gh repo view atiksh17/<repo> --json visibility -q .visibility
```

Expected: `PRIVATE`. **Stop and delete the repo if it reports anything else** —
`credentials.env` is committed.

- [ ] **Step 6: Verify the install from GitHub, not from disk**

```bash
SCRATCH2=$(mktemp -d) && cd "$SCRATCH2"
git clone https://github.com/atiksh17/<repo>.git && cd <repo>
./setup.sh
```

Expected: `ready.` and exit 0. This is the exact experience the end user gets.

- [ ] **Step 7: Commit any fixes and push**

```bash
git add -A
git commit -m "chore: fixes found by clean-clone verification"
git push
```

---

### Task 9: Live end-to-end run

The last project's rule: one real call beats any number of unit tests. Neither mode is done until it has run for real.

**Files:**
- Modify: `docs/reference/endpoints.md` (paste the real discovery response)
- Modify: `.claude/skills/event-streams/SKILL.md` (correct anything the real run contradicts)

**Interfaces:**
- Consumes: the shipped repo from Task 8
- Produces: a verified skill

- [ ] **Step 1: Run test mode for real**

In the clean clone, ask the agent to test a keyword set. Confirm it: warns about
the duration up front, backgrounds the call, polls, renders a table, states the
pass rate, and offers a prompt rewrite. Confirm it never touches NocoDB.

- [ ] **Step 2: Record the real response and fix any drift**

Paste the actual response into `docs/reference/endpoints.md`. If any field name
differs from what the skill expects, the skill is wrong — fix the skill.

- [ ] **Step 3: Run production mode for real on a small range**

Ask for ~5 rows from a real stream table. Confirm it: refuses `Streams` and
`Template` as targets, **asks for job titles before spending anything**,
confirms the scope, isolates a failed company without aborting, writes
`data/<table>-YYYY-MM-DD.csv`, and reports coverage honestly.

- [ ] **Step 4: Confirm nothing was written to NocoDB**

```bash
set -a; . ./credentials.env; set +a
curl -sS -X POST "${NOCODB_MCP_URL}" -H "xc-mcp-token: ${NOCODB_MCP_TOKEN}" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{
       "name":"countRecords","arguments":{"tableName":"<the table used>"}}}'
```

Expected: the same count as before the run.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "fix: corrections from the first live run

Field names now come from a real response rather than an assumed shape."
git push
```

- [ ] **Step 6: Write the lessons file**

Create `~/.claude/Lessons/event-streams-skill-repo.md` covering: project-local
skill discovery verified in both harnesses; `codex mcp add` having no `--header`
flag and `http_headers` being the only route to NocoDB; the 15-minute call
against the 10-minute foreground cap; the decision to commit credentials in a
private repo and what that costs; and anything the live runs contradicted.

---

## Self-Review

**Spec coverage.** Repo layout → Task 1. Install, both paths → Tasks 2, 3.
MCP wiring incl. the Codex `http_headers` workaround → Tasks 2, 3. Secrets and
the read-only token → Tasks 2, 4. Test mode incl. the backgrounding constraint
and failure table → Task 5. Production mode incl. reserved tables, job titles,
output convention → Task 6. Documentation → Task 7. All six verification points
→ Tasks 8, 9. Every open item in the spec is resolved by Task 2 (keys), Task 4
(tool names, table names), Task 8 (repo name), or Task 9 (real response).

**Placeholders.** `<repo>` in Tasks 7–9 and `<tool>` in Task 6 are inputs the
task itself resolves, and each says where the value comes from. No step defers
work to a later "TBD".

**Type consistency.** `credentials.env` defines `AI_ARK_API_KEY`,
`NOCODB_MCP_TOKEN`, `NOCODB_MCP_URL`, `DISCOVERY_URL` in Task 2 and every later
task uses those four names. `AI_ARK_URL` is constructed only inside `setup.sh`.
Test scripts are `test_layout.sh`, `test_configs.sh`, `test_setup.sh`,
`test_docs.sh` throughout, and `run_all.sh` invokes exactly those four. CSV
columns are stated identically in Task 6 and the spec.
