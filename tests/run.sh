#!/bin/bash
# Runs every test against both clients (Forever and retail/Midnight).
# Usage: tests/run.sh            (from anywhere; needs lua5.1)
#        UPDATE_GOLDEN=1 tests/run.sh   to re-record the scenario goldens
cd "$(dirname "$0")"
ADDON=../MythicScoreboard
SUITES="meter_tests lifecycle_tests archive_tests stats_ui_tests history_tests stats_poll_test
        hover_tests stats_manage_tests history_repair_tests fight_tests clear_tests account_tests
        wc_layout_test compare_tests perf_tests migrations_tests layout_tests fixes_tests runstats_tests slice_tests pool_tests locale_tests pixel_tests openfight_tests layering_tests $EXTRA"
fail=0
for f in $SUITES; do
  for t in MythicScoreboard_Forever.toc MythicScoreboard.toc; do
    out=$(timeout 120 lua5.1 $f.lua $ADDON $t 2>&1); rc=$?
    if [ $rc -ne 0 ]; then fail=1; echo "== $f ($t)"; echo "$out" | tail -15; fi
  done
done
for pair in MythicScoreboard_Forever.toc:golden_forever.txt MythicScoreboard.toc:golden_retail.txt; do
  toc=${pair%%:*}; gold=${pair##*:}
  lua5.1 scenario.lua $ADDON $toc > /tmp/msb_scenario.txt 2>&1
  if [ -n "$UPDATE_GOLDEN" ]; then cp /tmp/msb_scenario.txt $gold
  elif ! diff -q /tmp/msb_scenario.txt $gold >/dev/null; then
    fail=1; echo "== scenario ($toc) differs from $gold"; diff /tmp/msb_scenario.txt $gold | head -20
  fi
done
out=$(python3 header_fit.py $ADDON 2>&1) || { fail=1; echo "== header_fit"; echo "$out" | tail -15; }
[ $fail -eq 0 ] && echo "ALL PASS"
exit $fail
