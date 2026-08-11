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
  f="${line%%:*}"
  rest="${line#*:}"           # "](link)"
  link="${rest#\]\(}"         # strip leading "]("
  link="${link%\)}"           # strip trailing ")"
  case "$link" in http*|\#*) continue;; esac
  target="$(dirname "$f")/${link%%#*}"
  [ -e "$target" ] || { echo "     broken: $f -> $link"; broken=1; }
done < <(grep -roE '\]\([^)]+\)' --include='*.md' . | grep -vE '(^|/)\.?superpowers/')
[ "$broken" -eq 0 ]
check "every relative markdown link resolves" $?

grep -q 'webhook/stream' README.md || grep -q 'setup.sh' README.md
check "README names the install command" $?

# The discovery endpoint rejects anything but these three literals, so the
# spelling in the docs is the contract. A "helpful" fix to JustGiving breaks
# every run.
SKILL=.claude/skills/event-streams/SKILL.md
grep -q '"sources": \["Google News", "Justgiving", "LinkedIn"\]' "$SKILL"
check "skill's request body sends sources, spelled exactly" $?
for s in 'Google News' 'Justgiving' 'LinkedIn'; do
  grep -q "\"$s\"" "$SKILL" && grep -q "\"$s\"" docs/reference/endpoints.md
  check "  ...\"$s\" documented in the skill and the reference" $?
done
grep -qi 'at least one' "$SKILL" && grep -qi 'at least one' docs/reference/endpoints.md
check "  ...and both say at least one source is required" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all doc checks passed"
