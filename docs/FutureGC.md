# HXCPP_FUTURE_GC — mostly-concurrent major collections

`-D HXCPP_FUTURE_GC` is an add-on to the generational collector
(`-D HXCPP_GC_GENERATIONAL` is required) that replaces stop-the-world *major*
collections with a mostly-concurrent mark cycle. It targets latency-sensitive
applications — games in particular — where a 5–20 ms full-collect stall is
visible as a dropped frame.

```
haxe ... -D HXCPP_GC_GENERATIONAL -D HXCPP_FUTURE_GC
```

No Haxe compiler changes are required: the design reuses the write-barrier
call sites the compiler already emits for the generational collector; the
barrier *implementations* (macros in `hx/GC.h`) switch behaviour at runtime.

## How a cycle works

1. **Quick-start trigger** — when a collect is requested and the projected
   heap occupancy exceeds the trigger ratio (default 0.7,
   `HXCPP_FUTURE_GC_TRIGGER`), the cycle starts in a *minimal* pause
   (~0.2-0.4 ms) instead of running a stop-the-world minor: mark ids are
   flipped (everything becomes white), the concurrent barriers are armed,
   the remembered set is handed to the markers and all roots (statics, GC
   roots, zombies, conservative thread stacks) are pushed onto the mark
   queue without being scanned.  Live nursery objects are promoted
   *concurrently* as part of the normal graph walk.  Below the trigger,
   ordinary minor collects run unchanged.

2. **Concurrent mark** — a coordinator thread drains the queue using the
   existing parallel-mark worker pool (default 2 workers,
   `HXCPP_FUTURE_GC_MARK_THREADS`) while the mutators keep running:

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

3. **Remark (stop-the-world, sub-millisecond typical)** — roots and stacks
   are re-scanned, per-thread chunks are flushed, dirty objects re-scanned,
   the residual queue drained with all workers, finalizers/weak refs/zombies
   processed, shadow row marks swapped into place (dead rows drop out) and
   the free lists rebuilt. Every ~15th cycle this pause performs a full
   reclaim to scrub stale alloc-start data before the 4-bit mark id wraps.

   The remark drain is *time-boxed* (default 4 ms,
   `HXCPP_FUTURE_GC_REMARK_BUDGET_MS`): if too much newly-live data surfaces
   (e.g. a large structure whose only reference migrated to a stack during
   the cycle), the world is resumed, marking continues concurrently and the
   remark is retried - the third attempt is unbounded.  This caps the
   worst-case pause instead of just the typical one.

Minor collects are unchanged (already short); between collects the heap may
grow by a nursery budget (default 32 MB, `HXCPP_FUTURE_GC_NURSERY_MB`) before
a minor is forced — survivors, not nursery size, drive the minor pause, so
this mostly trades memory for throughput.

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
  (ms), `104` = cycle currently active.

## Environment knobs

| Variable | Default | Meaning |
|---|---|---|
| `HXCPP_FUTURE_GC_MARK_THREADS` | 2 | worker threads used for concurrent marking |
| `HXCPP_FUTURE_GC_TRIGGER` | 0.7 | projected-occupancy ratio that starts a cycle |
| `HXCPP_FUTURE_GC_NURSERY_MB` | 32 | heap growth allowed between minor collects |
| `HXCPP_FUTURE_GC_REMARK_BUDGET_MS` | 4 | remark drain budget before resuming + retrying |
| `HXCPP_FUTURE_GC_VERBOSE` | off | log cycle/pause timings to stdout |

## Tracy

With `-D HXCPP_TRACY` the collector emits zones on every thread:

* red — stop-the-world work (`GC collect`, `GC remark`)
* orange — concurrent work (`GC concurrent cycle`, `GC mark`)
* yellow — mutators waiting (`GC pause`, `GC wait for cycle`)
* plots — `GC/used (MB)`, `GC/reserved (MB)`
* GC threads are named (`hxcpp gc coordinator`, `hxcpp gc worker N`)

## Measured results (M-series macOS, arm64, `test/future-gc`)

Game-style benchmark (150k-entity world, ~100 MB live, heavy per-frame
allocation + mutation, 3000 frames):

| | classic generational | FUTURE_GC |
|---|---|---|
| avg frame | 0.22 ms | 0.24 ms |
| p99.9 frame | 4.1 ms | 1.2–1.4 ms |
| **max frame** | **11.2 ms** | **1.3–2.9 ms** |
| cycle-start pause | — | avg 0.27 ms, max 0.32 ms |
| remark pause | — | avg 0.77 ms, max 0.97 ms |

All stop-the-world GC pauses during gameplay are sub-millisecond; the frame
tail above remark time is ordinary frame work colliding with a pause.

Binary-trees (depth 19): 635 ms → 751 ms (+18%).
Short-lived allocation rate: 284 M/s → 288 M/s (unchanged).

## Files

* `src/hx/gc/Immix.cpp` — cycle state machine, coordinator thread, shade /
  dirty / allocate-black, shadow rows, remark.
* `include/hx/GC.h` — barrier macros, inline allocate-black hook, scan clamp.
* `include/hx/GcTypeInference.h`, `src/hx/Hash.h`, `src/Array.cpp`,
  `include/Array.h` — concurrent-safe container scanning + bulk barriers.
* `test/future-gc/` — correctness stress tests and benchmarks (`./run.sh`).
