#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/test_layout.sh tests/test_configs.sh tests/test_setup.sh tests/test_probe.sh tests/test_trust_entry.sh tests/test_docs.sh; do
  echo; bash "$t" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "SUITE PASSED" || echo "SUITE FAILED"
exit "$rc"
