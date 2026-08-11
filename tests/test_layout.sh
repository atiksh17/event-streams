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

[ -x setup.sh ]
check "setup.sh is executable" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all layout checks passed"
