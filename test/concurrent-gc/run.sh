#!/bin/bash
# Correctness + benchmark suite for -D HXCPP_GC_CONCURRENT
# Usage: ./run.sh               (build + run everything)
#        ./run.sh correctness   (build + run the correctness tests only, as on CI)
# Extra haxe defines (an arch flag on CI) can be given with HXCPP_TEST_DEFINES,
#  for example HXCPP_TEST_DEFINES="-D HXCPP_ARM64"
set -e
# A failing test piped into tail must stop the suite too
set -o pipefail
cd "$(dirname "$0")"

MODE="${1:-all}"
if [ "$MODE" != "all" ] && [ "$MODE" != "correctness" ]; then
   echo "unknown mode: $MODE (expected all or correctness)"
   exit 1
fi

GEN="-D HXCPP_GC_GENERATIONAL ${HXCPP_TEST_DEFINES:-}"
FUT="$GEN -D HXCPP_GC_CONCURRENT"


echo "== building =="
haxe -main Smoke     -cp . -cpp bin/smoke-gen    $GEN
haxe -main Smoke     -cp . -cpp bin/smoke-conc    $FUT
haxe -main Stress    -cp . -cpp bin/stress-gen   $GEN
haxe -main Stress    -cp . -cpp bin/stress-conc   $FUT
haxe -main RemarkStorm -cp . -cpp bin/storm-conc  $FUT
haxe -main HeapBound -cp . -cpp bin/heapbound-conc  $FUT -D HXCPP_GC_CONCURRENT_HEAP_MARGIN_MB=32
haxe -main LargeStringShade -cp . -cpp bin/largestring-conc  $FUT
haxe -main LargeObjectShade -cp . -cpp bin/largeobject-conc  $FUT
haxe -main ArrayResizeRace -cp . -cpp bin/arrayrace-conc  $FUT
if [ "$MODE" = "all" ]; then
   haxe -main Trees     -cp . -cpp bin/trees-gen    $GEN
   haxe -main Trees     -cp . -cpp bin/trees-conc    $FUT
   haxe -main AllocRate -cp . -cpp bin/alloc-gen    $GEN
   haxe -main AllocRate -cp . -cpp bin/alloc-conc    $FUT
   haxe -main GameBench -cp . -cpp bin/bench-gen    $GEN
   haxe -main GameBench -cp . -cpp bin/bench-conc    $FUT
fi

echo "== correctness =="
bin/smoke-gen/Smoke   | tail -1
bin/smoke-conc/Smoke   | tail -1
bin/stress-gen/Stress | tail -1
for i in 1 2 3; do bin/stress-conc/Stress 1200 | tail -1; done
HXCPP_GC_CONCURRENT_REMARK_BUDGET_MS=0.5 bin/storm-conc/RemarkStorm | tail -1
bin/heapbound-conc/HeapBound | tail -2
HXCPP_GC_CONCURRENT_TRIGGER=0.15 bin/largestring-conc/LargeStringShade | tail -2
HXCPP_GC_CONCURRENT_TRIGGER=0.15 bin/largeobject-conc/LargeObjectShade | tail -2
HXCPP_GC_CONCURRENT_TRIGGER=0.15 bin/arrayrace-conc/ArrayResizeRace 20 | tail -2

if [ "$MODE" = "correctness" ]; then
   echo "ALL CORRECTNESS TESTS PASSED"
   exit 0
fi

echo "== benchmarks (classic vs concurrent) =="
echo "-- trees --";      bin/trees-gen/Trees 19 | grep time;  bin/trees-conc/Trees 19 | grep time
echo "-- alloc rate --"; bin/alloc-gen/AllocRate | head -1;   bin/alloc-conc/AllocRate | head -1
echo "-- game frames --"
bin/bench-gen/GameBench 3000 150000 | grep -E "frame ms"
bin/bench-conc/GameBench 3000 150000 | grep -E "frame ms|concurrent"
echo "ALL DONE"
