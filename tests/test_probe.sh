#!/usr/bin/env bash
# Unit tests for setup.sh's probe_codex_stream_compat.
#
# This function decides whether a healthy-looking MCP server is actually
# usable from Codex. Two bugs shipped in it before this file existed, and
# neither was catchable by the rest of the suite, because test_setup.sh only
# ever exercises `./setup.sh --configs-only` — a path that never reaches the
# probe. Both bugs were found by hand afterwards:
#
#   1. an unguarded `grep` under `set -euo pipefail` killed the whole script,
#      silently, when a response carried no content-type header;
#   2. a catch-all branch reported a genuine non-2xx failure (a wrong NocoDB
#      token answers application/json too) as the known upstream SSE quirk.
#
# So the cases below are regression tests for real defects, not hypotheticals.
#
# `curl` is shadowed by a shell function, so nothing here touches the network
# and no credential is needed.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   - $1"; else echo "  FAIL - $1"; fails=$((fails+1)); fi; }

EVENT_STREAMS_SOURCE_ONLY=1 . ./setup.sh
# setup.sh sets `set -euo pipefail`, and sourcing brings that into this shell.
# Under `set -e` the first deliberately-failing assertion below would kill the
# test run instead of being recorded as a FAIL. Turn it back off - the probe
# itself is still exercised with pipefail active, which is what matters.
set +e

echo "probe:"

type probe_codex_stream_compat >/dev/null 2>&1
check "probe function is reachable without running an install" $?

# Each case sets FIXTURE to the raw header block curl would emit.
run_probe() {
  curl() { printf '%s' "$FIXTURE"; }   # shadows the real binary
  rc=0
  codex_stream_warned=0
  # Output goes to a file, NOT `out=$(...)`. Command substitution runs the
  # probe in a subshell, where its `rc=1` and `codex_stream_warned=1`
  # assignments die with the subshell and never reach us - the test would
  # then report a pass for every failure case. setup.sh calls the probe
  # directly, so this is a test-harness concern only.
  probe_codex_stream_compat "testsrv" "https://example.invalid" >"$TMPOUT" 2>&1
  probe_rc=$rc
  probe_warned=$codex_stream_warned
  out=$(cat "$TMPOUT")
  unset -f curl
}
TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

# --- 1. SSE reply: usable from Codex -----------------------------------------
FIXTURE='HTTP/2 200
content-type: text/event-stream
'
run_probe
[ "$probe_rc" -eq 0 ] && [ "$probe_warned" -eq 0 ] && echo "$out" | grep -q "can use this server"
check "text/event-stream -> clears, rc unchanged, no warning" $?

# --- 2. JSON reply on 200: the known SSE quirk -------------------------------
FIXTURE='HTTP/2 200
content-type: application/json
'
run_probe
[ "$probe_rc" -eq 0 ] && [ "$probe_warned" -eq 1 ]
check "200 + application/json -> warns as the SSE quirk, rc stays 0" $?
echo "$out" | grep -qi "Transport channel closed"
check "  ...and names the error a user would actually search for" $?

# --- 3. Non-2xx: a real failure, NOT the quirk -------------------------------
# Regression: a wrong NocoDB token answers 404 with application/json. Reporting
# that as an unfixable upstream bug sends someone hunting the wrong thing.
FIXTURE='HTTP/2 404
content-type: application/json
'
run_probe
[ "$probe_rc" -eq 1 ]
check "404 -> rc=1, treated as a real failure" $?
[ "$probe_warned" -eq 0 ]
check "  ...and NOT excused as the SSE quirk" $?
echo "$out" | grep -q "real failure, not the SSE quirk"
check "  ...and says so explicitly" $?

# --- 4. No content-type header at all ----------------------------------------
# Regression: this is what killed the script. A bare 502 from a fronting proxy
# has exactly this shape, and an unguarded `grep` aborted setup.sh with no
# output whatsoever - strictly worse than the behaviour it replaced.
#
# This case MUST run under `set -e`. The bug is a non-zero grep propagating
# through pipefail and tripping errexit; with errexit off it cannot reproduce
# at all. An earlier version of this test ran it with `set +e` like the others
# and passed happily with the bug deliberately reinstated - a test that could
# never fail. Hence the subshell: it re-enables errexit, and the trailing
# marker only prints if the probe returned instead of taking the shell down.
FIXTURE='HTTP/2 502
'
(
  set -euo pipefail
  curl() { printf '%s' "$FIXTURE"; }
  rc=0; codex_stream_warned=0
  probe_codex_stream_compat "testsrv" "https://example.invalid" >/dev/null 2>&1
  printf 'SURVIVED rc=%s\n' "$rc"
) > "$TMPOUT" 2>&1
grep -q '^SURVIVED' "$TMPOUT"
check "no content-type header does not abort the script under set -e" $?
grep -q '^SURVIVED rc=1$' "$TMPOUT"
check "  ...and is reported as a real failure (rc=1)" $?

# --- 5. No response at all (connection refused) ------------------------------
FIXTURE=''
run_probe
[ "$probe_rc" -eq 1 ] && echo "$out" | grep -q "did not answer the probe at all"
check "empty response -> rc=1, reported as no answer" $?

# --- 6. Header casing and CRLF are handled -----------------------------------
# Real servers send CRLF, and header names are case-insensitive per RFC 9110.
FIXTURE=$(printf 'HTTP/1.1 200 OK\r\nContent-Type: TEXT/EVENT-STREAM\r\n')
run_probe
[ "$probe_warned" -eq 0 ] && [ "$probe_rc" -eq 0 ]
check "CRLF + uppercase Content-Type still recognised as SSE" $?

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) failed"; exit 1; fi
echo "all probe checks passed"
