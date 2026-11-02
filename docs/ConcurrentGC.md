# HXCPP_GC_CONCURRENT — mostly-concurrent major collections

`-D HXCPP_GC_CONCURRENT` is an add-on to the generational collector
(`-D HXCPP_GC_GENERATIONAL` is required) that replaces stop-the-world *major*
collections with a mostly-concurrent mark cycle. It targets latency-sensitive
applications — games in particular — where a 5–20 ms full-collect stall is
visible as a dropped frame.

```
haxe ... -D HXCPP_GC_GENERATIONAL -D HXCPP_GC_CONCURRENT
```

No Haxe compiler changes are required: the design reuses the write-barrier
call sites the compiler already emits for the generational collector; the
barrier *implementations* (macros in `hx/GC.h`) switch behaviour at runtime.

## How a cycle works

1. **Quick-start trigger** — when a collect is requested and the projected
   heap occupancy exceeds the trigger ratio (default 0.7,
   `HXCPP_GC_CONCURRENT_TRIGGER`), the cycle starts in a *minimal* pause
   (~0.2-0.4 ms) instead of running a stop-the-world minor: mark ids are
   flipped (everything becomes white), the concurrent barriers are armed,
   the remembered set is handed to the markers and all roots (statics, GC
   roots, zombies, conservative thread stacks) are pushed onto the mark
   queue without being scanned.  Live nursery objects are promoted
   *concurrently* as part of the normal graph walk.  Below the trigger,
   ordinary minor collects run unchanged.

2. **Concurrent mark** — a coordinator thread drains the queue using the
   existing parallel-mark worker pool (default 2 workers,
   `HXCPP_GC_CONCURRENT_MARK_THREADS`) while the mutators keep running:

   * **Write barrier (Dijkstra, incremental update)** — storing a pointer to
     an unmarked object *shades* it: the mutator marks it and queues it
     through its own chunk list. Because the hand-off uses acquire/release
     CAS, marker threads always observe fully initialised objects — this is
     what makes concurrent traversal safe on weakly-ordered CPUs (arm64).
   * **Pessimistic/bulk barriers** (`blit`, array/bucket reallocation, hash
     re-bucketing, `Reflect`-style stores) — the *object* is queued on a
     dirty list and re-scanned consistently during the final pause.
   * **Allocate-black** — objects created during the cycle get fully marked
     headers and can never be swept this cycle; the marker never needs to
     read their contents.
   * **Row marks go to a shadow slab**, so the primary row marks that
     allocation and lazy reclaim depend on stay valid for the whole cycle.
   * Concurrent scans of arrays/hashes are bounded by the size of the
     allocation being scanned, so racing a resize can never read out of
     bounds; any element such a torn scan could miss is covered by a barrier.
   * The heap may grow during a cycle rather than ever making a mutator wait
     for the marker (the cycle is asked to *accelerate* instead).

3. **Remark (stop-the-world, ~0.2-0.4 ms)** — roots and stacks are
   re-scanned, per-thread chunks flushed, dirty objects re-scanned, the
   residual queue drained, finalizers/weak refs/zombies processed and dead
   large objects released (safe here: marking is complete, so an unmarked
   header provably means dead).

   The drain is *time-boxed* (default 4 ms,
   `HXCPP_GC_CONCURRENT_REMARK_BUDGET_MS`): if too much newly-live data surfaces
   (e.g. a large structure whose only reference migrated to a stack during
   the cycle), the world is resumed, marking continues concurrently and the
   remark is retried - the third attempt is unbounded.  This caps the
   worst-case pause instead of just the typical one.

4. **Concurrent sweep preparation** — with the world running again, the
   shadow row marks are swapped into place and every block is recounted,
   using the per-block zero-lock to exclude allocators and ownership epochs
   to leave actively-bumped blocks alone.  Every ~15th cycle this pass
   performs a full per-block reclaim, scrubbing stale alloc-start data
   before the 4-bit mark id wraps (conservative-scan safety).

5. **Publish (stop-the-world, ~0.1-0.3 ms)** — fresh free lists are built
   from the swept blocks (skipping any with a live bump allocator) and the
   memory accounting/growth budgets are updated.

Between collects the heap may grow by a nursery budget (default 32 MB,
`HXCPP_GC_CONCURRENT_NURSERY_MB`) before a minor is forced. Survivors, not
nursery size, drive the minor pause, so this mostly trades memory for
throughput. The budget only binds while the heap is at its cap: a heap that
grew during concurrent cycles keeps its free blocks, and the minors then come
when those are used up, whatever the budget.

## Minor collections

A minor collection (`Collect`) is a stop-the-world pause of the allocating
thread. With `HXCPP_GC_CONCURRENT_VERBOSE` every minor logs its phases:

```
Concurrent GC: minor pause 1.868ms (stop=0.049 mark=1.499 sweepPrep=0.320 cycleStart=0.000)
Concurrent GC: minor phases wait=0.000 remembered=0.048(8829) markInit=0.035 statics=0.097
  roots=0.003 stacks=0.070 mark=1.291 finalizers=0.002 countRows=0.266 large=0.001
  other=0.000 freeList=0.050 zeroStart=0.003 blocks=8446 free=8331
```

(times in ms, one line in the log; `remembered` shows the remembered set
size, `blocks` and `free` the heap and free list sizes in 32 KB blocks)

`stacks` is the conservative scan of the thread stacks, `mark` the marking of
the survivors with the worker pool, `countRows` the per-block line count of
the whole heap, `freeList` the rebuild of the free block list. What keeps the
pause short:

* The collecting thread marks with the pool workers (it drains the shared
  queue while they wake up) and counts blocks with them, instead of sleeping
  until they are done. The workers claim blocks to count by batches of 16:
  one atomic increment per block on the shared cursor cost more than the
  count itself.
* The free block list is ordered with a counting sort on the hole size in
  lines (an exact key), not `std::sort` with a comparison that reads two
  block headers. The order is the same; equal keys keep the block order.
* `MarkClassStatics` walks a flat list of the registered classes (rebuilt
  when a class is registered, in address order) instead of the class map.
  `mMarkFunc` and `__meta__` are still tested on every walk, since they can
  be set after registration.
* Stack values that may point into the nursery (no allocation start bit) are
  resolved after the stack scan, sorted, one block at a time, so each nursery
  hole is walked once instead of once per value. The verifier
  (`HXCPP_GC_CONCURRENT_VERIFY`) checks every answer against the one-value
  walk.

The nursery fill can be read cheaply, for example to schedule a minor
between two frames: `Gc.memInfo64(118)` (bytes handed to the allocators
since the last collection) against `Gc.memInfo64(119)` (room for new objects
at that collection: free lines plus allowed growth); a minor comes when the
first reaches the second. Note that an explicit `Gc.run(false)` waits for a
concurrent cycle when its pause starts one (explicit collects are
synchronous), so a scheduler must expect that wait.

## Semantics & compatibility

* `Gc.run(true)` / `__hxcpp_collect(true)` maps to `InternalCollect(major,
  compact)` and intentionally remains a **synchronous classic full collect**
  (the predictable escape hatch; also the only path that compacts/releases
  block groups). Automatic majors are the concurrent ones.
* If a collect is requested while a cycle is in flight, the caller waits
  GC-safely for the cycle instead (the remark rebuilds the free lists).
* Incompatible defines: `HXCPP_SINGLE_THREADED_APP`, `HXCPP_GC_VERIFY`,
  `HXCPP_GC_DEBUG_ALWAYS_MOVE` (compile-time `#error`).
  `HXCPP_GC_MOVING` is allowed; moving/compaction only happens in classic
  (explicit/fallback) full collects, never concurrently.
* Weak refs, weak hashes, finalizers and zombies are processed in the remark
  pause with marking complete — same semantics as a classic full collect.
* `Gc.memInfo64()` extensions: `100` = completed cycles, `101` = last remark
  pause (ms), `102` = max remark pause (ms), `103` = last full cycle length
  (ms), `104` = cycle currently active, `105` = last publish pause (ms),
  `106` = max publish pause (ms). Mutator pauses (`Collect`): `107` = minor
  collections, `108` = last minor pause (ms), `109` = max minor pause (ms),
  `110` = total minor pause time (ms), `111` to `114` = total minor time spent
  stopping the world, marking, preparing the sweep and starting a cycle (ms),
  `115` = full collections, `116` = their total pause time (ms), `117` =
  allocation volume in bytes (holes handed to the allocators plus large
  allocations), for allocation rates. Nursery fill: `118` = bytes handed to
  the allocators since the last collection that rebuilt the free lists,
  `119` = room for new objects at that collection (a minor comes when `118`
  reaches `119`). `120` = bytes of the objects found live in blocks by the
  last full collection (counted exactly, without the line fragmentation that
  `MEM_INFO_USAGE` includes; add `MEM_INFO_LARGE` for the large objects): with
  `Gc.run(true)` first, the live size for leak checks.

## Environment knobs

| Variable | Default | Meaning |
|---|---|---|
| `HXCPP_GC_CONCURRENT_MARK_THREADS` | 2 | worker threads used for concurrent marking |
| `HXCPP_GC_CONCURRENT_TRIGGER` | 0.7 | projected-occupancy ratio that starts a cycle |
| `HXCPP_GC_CONCURRENT_NURSERY_MB` | 32 | heap growth allowed between minor collects |
| `HXCPP_GC_CONCURRENT_REMARK_BUDGET_MS` | 4 | remark drain budget before resuming + retrying |
| `HXCPP_GC_CONCURRENT_VERBOSE` | off | log cycle/pause timings and the minor pause phases to stdout |

## Tracy

Two build flavours:

* `-D HXCPP_TRACY -D HXCPP_TRACY_ON_DEMAND` — GC zones/plots only, minimal
  overhead, numbers closest to a non-profiled build.
* add `-D HXCPP_TELEMETRY` — additionally emits per-function Haxe zones and
  enables `cpp.vm.tracy.TracyProfiler` (frame marks etc.) at some mutator
  overhead.

The vendored client is tracy 0.12.0 - the profiler/capture tools must match
(0.12.x; 0.13 is protocol-incompatible).

The collector emits zones on every thread:

* red — stop-the-world work (`GC collect`, `GC remark`)
* orange — concurrent work (`GC concurrent cycle`, `GC mark`)
* yellow — mutators waiting (`GC pause`, `GC wait for cycle`)
* plots — `GC/used (MB)`, `GC/reserved (MB)`
* GC threads are named (`hxcpp gc coordinator`, `hxcpp gc worker N`)

## Measured results (M-series macOS, arm64, `test/concurrent-gc`)

Game-style benchmark (150k-entity world, ~100 MB live, heavy per-frame
allocation + mutation, 3000 frames):

| | classic generational | GC_CONCURRENT |
|---|---|---|
| avg frame | 0.24 ms | 0.22 ms |
| p99.9 frame | 4.3 ms | 1.0–1.4 ms |
| **max frame** | **11.4 ms** | **1.1–2.4 ms** |
| cycle-start pause | — | avg 0.31 ms, max 0.86 ms |
| remark pause | — | avg 0.22 ms, max 0.42 ms |
| publish pause | — | avg 0.14 ms, max 0.29 ms |

Every stop-the-world GC pause during gameplay is well under one
millisecond, fitting a 1 ms frame budget; the frame tail above pause time
is ordinary frame work colliding with a pause.

Binary-trees (depth 19): 635 ms → 717 ms (+13%).
Short-lived allocation rate: ~285 M allocs/s in both.

### Minor pause (2026-11-01, M4 Max, other builds running: load 4 to 10)

GPUI port bench (`ceramic-gpui/test/bench`, default Ceramic build with the
hxcpp checks, 300 frames x 3 runs x 3 alternating processes, the same
generated C++ linked against each hxcpp; medians):

| Scenario | minor pause before | after | minor time per 300 frames before | after | frame p99 before | after |
|---|---|---|---|---|---|---|
| cards full (61 to 63 minors) | 2.50 ms | 1.69 ms | 157.5 ms | 110.3 ms | 21.11 ms | 20.38 ms |
| hover full (18) | 2.16 ms | 1.21 ms | 38.7 ms | 21.8 ms | 10.13 ms | 9.25 ms |
| scroll-table full (16) | 2.15 ms | 1.26 ms | 35.1 ms | 20.9 ms | 8.79 ms | 7.67 ms |
| story-dense full (16 to 17) | 1.98 ms | 1.05 ms | 33.4 ms | 17.8 ms | 9.24 ms | 7.75 ms |

The largest minor pause of a whole bench process went from 3.8 to 4.1 ms down
to 2.3 to 2.6 ms. Median frame times do not move (within 1 %). Phases of the
same runs (`HXCPP_GC_CONCURRENT_VERBOSE`, about 470 minors each, median ms):

| Phase | before | after | change |
|---|---|---|---|
| whole pause | 2.155 | 1.360 | |
| statics | 0.132 | 0.100 | flat class list |
| stacks | 0.150 | 0.102 | sorted nursery lookups |
| mark | 0.823 | 0.726 | collecting thread marks too |
| countRows | 0.478 | 0.212 | collecting thread counts too, batched claims |
| freeList | 0.331 | 0.050 | counting sort |

Each change was measured alone first by alternating it on and off from one
minor to the next in the same process (same heap, same load): free list
0.45 to 0.07 ms, row count 0.60 to 0.24 ms (batches and the collecting
thread both needed: either alone gives 0.46 to 0.48 ms), statics 0.13 to
0.10 ms, stacks 0.15 to 0.10 ms, mark 1.00 to 0.91 ms (p10 0.54 to 0.40 ms).

Not changed, because the breakdown does not point at them on these
workloads: finalizers and weak references (0.002 ms), the remembered set
(0.03 ms for 4000 objects), the cycle start inside a minor (2 minors out of
500), the block mark clear (0.035 ms). A row count limited to the blocks
touched since the last minor was tried and dropped: on a GPUI heap every
block is touched between two minors (the mutator uses the holes of the whole
heap). `HXCPP_GC_CONCURRENT_NURSERY_MB` 16, 32, 64 and 128 give the same
minor count and pauses on the GPUI bench: the heap grew during concurrent
cycles (to about 450 MB for about 100 MB live) and the minors come when its
free blocks are used up, so the budget does not bind there.

`test/concurrent-gc` (8 alternating runs, medians): GameBench frame p50
0.260 → 0.255 ms, p99 0.935 → 0.927 ms, p99.9 2.34 → 1.58 ms, max 3.39 →
2.04 ms (one minor per run; the cycles dominate); Trees 961 → 949 ms;
AllocRate 107 → 105 ms. GcBench (Ceramic, churn mode, 3 alternating hidden
runs): work p50 1.06 to 1.11 ms and p99 2.25 to 2.52 ms in both, no dropped
frame difference.

### Heap growth during concurrent cycles (2026-11-02, M4 Max, load 7 to 40: other builds running)

Measured with the soak mode of the GPUI port bench (`GPUI_BENCH_SOAK_SECONDS`
in `ceramic-gpui/test/bench`: memory sampled every 5 s for 30 minutes, the
live size after `Gc.run(true)` every minute), default Ceramic build:

| Scenario (30 min) | live (memInfo 120 + large) | reserved after 3 min | after 30 min | process RSS |
|---|---|---|---|---|
| cards full | 17.9 to 18.1 MB | 549 MB | 1264 MB (+26 MB/min) | 1.44 GB |
| gallery-input-scroll cached | 51 to 74 MB (used lines) | 409 MB | 823 MB (+14 MB/min) | 0.98 GB |

The live size is flat (no leak in the program), but the heap never stops
growing. What grows it (counted per growth site, cards full, 30 s):

* A cycle almost always starts by the quick-start, inside a collect that was
  requested because the free list is empty. Every object allocated during
  the cycle (allocate-black) then goes to new blocks: `allowMoreBlocks` lets
  the heap grow without limit while a cycle is active, so that mutators never
  wait for the marker. Those blocks are free again after the publish, but the
  next quick-start again comes with an empty free list. About 2/3 of the
  growth is in this path, most of the rest is the "prefer growing" path right
  after the quick-start (the same thing). The GPUI bench allocates about
  1.5 GB/s on cards full: a few MB per cycle.
* A heap that grew lowers the occupancy ratio, so cycles come less often,
  but each one still adds blocks: the heap grows like the square root of
  time, with no bound. `HXCPP_GC_CONCURRENT_NURSERY_MB` does not bind (it
  only limits growth outside cycles), and nothing shrinks the heap (without
  `HXCPP_GC_MOVING` even `Gc.run(true)` keeps every block group).
* While a pause is requested (remark, publish), an allocating thread that
  claims a block sees the request, drops the block's holes, and claims
  another block at its next allocation, until the free list is empty: it
  only stops in `GetFreeBlock` once `GetNextFree` fails. Seen as about 2700
  blocks claimed for 7 MB of allocation during one cycle, and remark stops
  of 1.5 to 3.6 ms waiting for that thread.

Tried, each measured alone against the same generated C++ (patch and test
kept in `ceramic-gpui/scratchpad/gcgrow/`):

1. Pause before claiming a block (check `gPauseForCollect` at the top of
   `GetFreeBlock`). Short bench (300 frames, 5 alternating runs): reserved
   3 to 6 % lower, frame median -2 to +4 %, max minor pause higher on some
   runs; over 30 s the heap grows like before. Not kept.
2. Early cycle start: when a cycle is due, start it while the free list
   still holds about twice what the last cycles used (counted in claimed
   free lines), so the cycle allocates into it. Without 1 the reserve is
   eaten by the block burning above; with 1 the heap stops growing: cards
   full 70 to 150 MB flat instead of 600 MB after 5 minutes. But the heap
   then stays close to the live size, minors and cycles come 2 to 15 times
   more often, and the frames are slower: GPUI short bench median +3 to +11 %,
   GameBench p50 0.21-0.23 to 0.26-0.27 ms (reserved 195 to 146 MB, cycles
   11 to 29). Not kept.
3. 1 and 2 plus a heap target between cycles of K times the memory in use
   after the last cycle. K = 2.5: cards full flat at 152 MB after 5 minutes
   (unchanged collector: 607 to 618 MB), gallery-input-scroll 245 MB (unchanged: 470 MB), but cards
   full frame median +2 to +10 % (5.1 cycles/s against 0.3); K = 3 and 4:
   cards 239 and 282 MB, median +13 and +20 %. gallery-input-scroll equal or
   faster. Not kept: memory drops clearly, but not without slowing frames.
   A larger nursery budget (64, 128 MB), a larger free space target
   (`HXCPP_TARGET_FREE_SPACE` 200, 400) or a later trigger (0.85) did not
   change that trade.

The cost seems to come from the cycles themselves (barriers armed and
allocate-black for a larger share of the frames), which a bounded heap makes
more frequent. The numbers were taken under heavy load (7 to 40); a quiet
machine A/B of option 3 is worth doing before deciding on it.

## Files

* `src/hx/gc/Immix.cpp` — cycle state machine, coordinator thread, shade /
  dirty / allocate-black, shadow rows, remark.
* `include/hx/GC.h` — barrier macros, inline allocate-black hook, scan clamp.
* `include/hx/GcTypeInference.h`, `src/hx/Hash.h`, `src/Array.cpp`,
  `include/Array.h` — concurrent-safe container scanning + bulk barriers.
* `test/concurrent-gc/` — correctness stress tests and benchmarks (`./run.sh`).
