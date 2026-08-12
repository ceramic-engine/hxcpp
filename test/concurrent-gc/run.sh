#!/bin/bash
# Correctness + benchmark suite for -D HXCPP_GC_CONCURRENT
# Usage: ./run.sh            (build + run everything)
set -e
cd "$(dirname "$0")"

GEN="-D HXCPP_GC_GENERATIONAL"
FUT="$GEN -D HXCPP_GC_CONCURRENT"


echo "== building =="
haxe -main Smoke     -cp . -cpp bin/smoke-gen    $GEN
haxe -main Smoke     -cp . -cpp bin/smoke-conc    $FUT
haxe -main Stress    -cp . -cpp bin/stress-gen   $GEN
haxe -main Stress    -cp . -cpp bin/stress-conc   $FUT
haxe -main Trees     -cp . -cpp bin/trees-gen    $GEN
haxe -main Trees     -cp . -cpp bin/trees-conc    $FUT
haxe -main AllocRate -cp . -cpp bin/alloc-gen    $GEN
haxe -main AllocRate -cp . -cpp bin/alloc-conc    $FUT
haxe -main GameBench -cp . -cpp bin/bench-gen    $GEN
haxe -main GameBench -cp . -cpp bin/bench-conc    $FUT
haxe -main RemarkStorm -cp . -cpp bin/storm-conc  $FUT

echo "== correctness =="
bin/smoke-gen/Smoke   | tail -1
bin/smoke-conc/Smoke   | tail -1
bin/stress-gen/Stress | tail -1
for i in 1 2 3; do bin/stress-conc/Stress 1200 | tail -1; done
HXCPP_GC_CONCURRENT_REMARK_BUDGET_MS=0.5 bin/storm-conc/RemarkStorm | tail -1

echo "== benchmarks (classic vs concurrent) =="
echo "-- trees --";      bin/trees-gen/Trees 19 | grep time;  bin/trees-conc/Trees 19 | grep time
echo "-- alloc rate --"; bin/alloc-gen/AllocRate | head -1;   bin/alloc-conc/AllocRate | head -1
echo "-- game frames --"
bin/bench-gen/GameBench 3000 150000 | grep -E "frame ms"
bin/bench-conc/GameBench 3000 150000 | grep -E "frame ms|concurrent"
echo "ALL DONE"
