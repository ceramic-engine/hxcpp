#!/bin/bash
# Correctness + benchmark suite for -D HXCPP_FUTURE_GC
# Usage: ./run.sh            (build + run everything)
set -e
cd "$(dirname "$0")"

GEN="-D HXCPP_GC_GENERATIONAL"
FUT="$GEN -D HXCPP_FUTURE_GC"


echo "== building =="
haxe -main Smoke     -cp . -cpp bin/smoke-gen    $GEN
haxe -main Smoke     -cp . -cpp bin/smoke-fut    $FUT
haxe -main Stress    -cp . -cpp bin/stress-gen   $GEN
haxe -main Stress    -cp . -cpp bin/stress-fut   $FUT
haxe -main Trees     -cp . -cpp bin/trees-gen    $GEN
haxe -main Trees     -cp . -cpp bin/trees-fut    $FUT
haxe -main AllocRate -cp . -cpp bin/alloc-gen    $GEN
haxe -main AllocRate -cp . -cpp bin/alloc-fut    $FUT
haxe -main GameBench -cp . -cpp bin/bench-gen    $GEN
haxe -main GameBench -cp . -cpp bin/bench-fut    $FUT
haxe -main RemarkStorm -cp . -cpp bin/storm-fut  $FUT

echo "== correctness =="
bin/smoke-gen/Smoke   | tail -1
bin/smoke-fut/Smoke   | tail -1
bin/stress-gen/Stress | tail -1
for i in 1 2 3; do bin/stress-fut/Stress 1200 | tail -1; done
HXCPP_FUTURE_GC_REMARK_BUDGET_MS=0.5 bin/storm-fut/RemarkStorm | tail -1

echo "== benchmarks (classic vs future) =="
echo "-- trees --";      bin/trees-gen/Trees 19 | grep time;  bin/trees-fut/Trees 19 | grep time
echo "-- alloc rate --"; bin/alloc-gen/AllocRate | head -1;   bin/alloc-fut/AllocRate | head -1
echo "-- game frames --"
bin/bench-gen/GameBench 3000 150000 | grep -E "frame ms"
bin/bench-fut/GameBench 3000 150000 | grep -E "frame ms|future"
echo "ALL DONE"
