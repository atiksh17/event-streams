#!/usr/bin/env bash
# Tests for the Codex trust-entry writer in setup.sh.
#
# This writes into the user's GLOBAL ~/.codex/config.toml, so a bug here breaks
# Codex everywhere, not just in this repo. One already did: the first version
# used `^\s*trust_level` and, because Python's `\s` matches newlines, the
# replacement ate the newline after the table header and produced
#
#     [projects."/path"]trust_level = "trusted"
#
# which is invalid TOML. Codex then refused to start at all, with only a parse
# error to go on. It survived the first run and appeared on the second, which
# is exactly the case an idempotency check is supposed to catch and didn't.
#
# Every case below runs the writer against a temp file. Nothing touches the
# real config.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
REPO="/tmp/some/clone/path"

# Runs setup.sh's embedded writer against $TMP/config.toml.
write_trust() {
  python3 - "$TMP/config.toml" "$REPO" <<'PY'
import re, sys
path, repo = sys.argv[1:3]
text = open(path).read()
original = text
text, n_removed = re.subn(
    r"\n?# >>> event-streams >>>.*?# <<< event-streams <<<\n?", "\n", text, flags=re.S)
header = f'[projects."{repo}"]'
if header in text:
    start = text.index(header) + len(header)
    nxt = re.search(r"\n\[", text[start:])
    end = start + (nxt.start() if nxt else len(text) - start)
    section = text[start:end]
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
PY
}

valid_toml() { python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$1" 2>/dev/null; }
trusted()    { python3 -c "
import tomllib,sys
d=tomllib.load(open(sys.argv[1],'rb'))
sys.exit(0 if d.get('projects',{}).get(sys.argv[2],{}).get('trust_level')=='trusted' else 1)" "$1" "$2"; }

echo "trust entry:"

# --- 1. empty config ---------------------------------------------------------
: > "$TMP/config.toml"
write_trust
valid_toml "$TMP/config.toml"; check "writes valid TOML into an empty config" $?
trusted "$TMP/config.toml" "$REPO"; check "  ...and the project is trusted" $?

# --- 2. run twice: the regression that broke Codex machine-wide --------------
write_trust
valid_toml "$TMP/config.toml"
check "SECOND run still produces valid TOML (the shipped bug)" $?
trusted "$TMP/config.toml" "$REPO"; check "  ...and the project is still trusted" $?
grep -q ']trust_level' "$TMP/config.toml" && collapsed=1 || collapsed=0
[ "$collapsed" -eq 0 ]
check "  ...header and key are not collapsed onto one line" $?
[ "$(grep -c "^\[projects\.\"$REPO\"\]" "$TMP/config.toml")" -eq 1 ]
check "  ...and the table header is not duplicated" $?

# --- 3. third run, for good measure ------------------------------------------
write_trust
valid_toml "$TMP/config.toml" && trusted "$TMP/config.toml" "$REPO"
check "third run is still valid and still trusted" $?

# --- 4. unrelated config must survive ----------------------------------------
cat > "$TMP/config.toml" <<'TOML'
[mcp_servers.node_repl]
command = "/some/binary"

[mcp_servers.node_repl.env]
FOO = "bar"

[projects."/another/repo"]
trust_level = "trusted"
TOML
write_trust
valid_toml "$TMP/config.toml"; check "valid TOML alongside pre-existing entries" $?
python3 -c "
import tomllib,sys
d=tomllib.load(open('$TMP/config.toml','rb'))
ok = 'node_repl' in d.get('mcp_servers',{}) \
     and d['mcp_servers']['node_repl']['env']['FOO']=='bar' \
     and d['projects']['/another/repo']['trust_level']=='trusted'
sys.exit(0 if ok else 1)"
check "  ...pre-existing servers and other projects untouched" $?
trusted "$TMP/config.toml" "$REPO"; check "  ...and our project was added" $?

# --- 5. an existing entry for our path, without trust_level ------------------
cat > "$TMP/config.toml" <<TOML
[projects."$REPO"]
some_other_key = "keep me"
TOML
write_trust
valid_toml "$TMP/config.toml"; check "adds trust_level to an existing section for our path" $?
trusted "$TMP/config.toml" "$REPO"; check "  ...and it is trusted" $?
grep -q 'some_other_key = "keep me"' "$TMP/config.toml"
check "  ...without dropping that section's other keys" $?

# --- 6. an existing entry already trusted, with neighbours -------------------
cat > "$TMP/config.toml" <<TOML
[projects."$REPO"]
trust_level = "untrusted"

[mcp_servers.keepme]
command = "x"
TOML
write_trust
valid_toml "$TMP/config.toml"; check "flips untrusted -> trusted" $?
trusted "$TMP/config.toml" "$REPO"; check "  ...and it is trusted" $?
python3 -c "
import tomllib,sys
d=tomllib.load(open('$TMP/config.toml','rb'))
sys.exit(0 if 'keepme' in d.get('mcp_servers',{}) else 1)"
check "  ...and the following table survives" $?

# --- 7. legacy global mcp_servers block is removed ---------------------------
cat > "$TMP/config.toml" <<TOML
[mcp_servers.keepme]
command = "x"

# >>> event-streams >>>
[mcp_servers.ai-ark]
url = "https://example.invalid"
# <<< event-streams <<<
TOML
write_trust
valid_toml "$TMP/config.toml"; check "removing a legacy block leaves valid TOML" $?
python3 -c "
import tomllib,sys
d=tomllib.load(open('$TMP/config.toml','rb'))
sys.exit(0 if 'ai-ark' not in d.get('mcp_servers',{}) and 'keepme' in d.get('mcp_servers',{}) else 1)"
check "  ...legacy ai-ark gone, unrelated server kept" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all trust-entry checks passed"
