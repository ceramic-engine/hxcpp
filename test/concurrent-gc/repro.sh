#!/bin/bash
# Reproduction tests of the races found by the concurrent GC audit.
# Usage: ./repro.sh [seconds per test] [test names...]
# Each test runs with the mark completeness verifier: objects that the
#  concurrent mark missed are listed in /tmp/cppia_gcmiss.log (the verifier
#  also marks them, which hides the crash they would cause).
# A test that fails does not stop the others.
set -u
set -o pipefail
cd "$(dirname "$0")"

SECONDS_PER_TEST="${1:-60}"
shift || true
TESTS=("$@")
if [ ${#TESTS[@]} -eq 0 ]; then
   TESTS=(ReproFinalizer ReproAnonDelete ReproVariantFlip ReproHashInsert ReproArrayGrow)
fi

FUT="-D HXCPP_GC_GENERATIONAL -D HXCPP_GC_CONCURRENT ${HXCPP_TEST_DEFINES:-}"
MISS_LOG=/tmp/cppia_gcmiss.log

for t in "${TESTS[@]}"; do
   echo "== $t"
   if ! haxe -main "$t" -cp . -cpp "bin/repro-$t" $FUT > "bin/repro-$t.build.log" 2>&1; then
      echo "BUILD FAILED (see bin/repro-$t.build.log)"
      continue
   fi
   for verify in ${REPRO_VERIFY_MODES:-0 1}; do
      : > "$MISS_LOG"
      start=$(date +%s)
      if [ "$verify" = "1" ]; then
         HXCPP_GC_CONCURRENT_VERIFY=1 HXCPP_GC_CONCURRENT_TRIGGER=0.15 "bin/repro-$t/$t" "$SECONDS_PER_TEST" > "bin/repro-$t.run.log" 2>&1
      else
         HXCPP_GC_CONCURRENT_TRIGGER=0.15 "bin/repro-$t/$t" "$SECONDS_PER_TEST" > "bin/repro-$t.run.log" 2>&1
      fi
      status=$?
      misses=$(grep -c "MISSED-OBJ" "$MISS_LOG" 2>/dev/null || true)
      echo "   verifier=$verify status=$status seconds=$(( $(date +%s) - start )) missed=${misses:-0}: $(tail -2 "bin/repro-$t.run.log" | tr '\n' ' ')"
   done
done
