#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the known-answer oracle for php-src that mayhem/build.sh produced. It runs a
# self-checking PHP script (mayhem/kat/run.php) on a clean (non-sanitized) PHP CLI built by
# build.sh (/mayhem/out/php-oracle). The script asserts concrete results of the Zend compile+execute
# path, serialize/unserialize, JSON and core builtins — the exact subsystems the fuzz targets drive
# — so a no-op / broken-engine PATCH fails it (anti-reward-hacking).
# Emits a CTRF (https://ctrf.io) summary and exits non-zero iff a test failed.
#
# NB: no `set -e` — grep returning non-zero (no match) under pipefail would abort before we emit CTRF.
set -uo pipefail
: "${SRC:=/mayhem}"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PHP="$SRC/out/php-oracle"
KAT="$SRC/mayhem/kat/run.php"

[ -x "$PHP" ] || { echo "FATAL: $PHP missing — mayhem/build.sh did not build the clean oracle CLI" >&2; emit_ctrf "php-cli-kat" 0 1 0; exit 1; }
[ -f "$KAT" ] || { echo "FATAL: $KAT missing" >&2; emit_ctrf "php-cli-kat" 0 1 0; exit 1; }

LOG=/tmp/php_kat.log
"$PHP" -n "$KAT" 2>&1 | tee "$LOG"

summary=$(grep -oE 'TESTS total=[0-9]+ passed=[0-9]+ failed=[0-9]+' "$LOG" | tail -1 || true)
passed=$(echo "$summary" | grep -oE 'passed=[0-9]+' | grep -oE '[0-9]+' || true)
failed=$(echo "$summary" | grep -oE 'failed=[0-9]+' | grep -oE '[0-9]+' || true)
: "${passed:=0}" "${failed:=0}"

if [ -z "$summary" ]; then
  echo "FATAL: php KAT did not complete (crash/abort?)" >&2
  emit_ctrf "php-cli-kat" "$passed" "$(( failed > 0 ? failed : 1 ))"
  exit 1
fi

emit_ctrf "php-cli-kat" "$passed" "$failed"
