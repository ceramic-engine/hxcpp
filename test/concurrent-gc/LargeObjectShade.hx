#if !macro
import cpp.vm.Gc;
#end
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// Write barrier on a large class instance while a concurrent cycle marks.
//
// Question checked here: ConcurrentGcShade returns early, without
//  pushReferrer, for an allocation whose header has a zero mark byte and a
//  zero size field (a large nursery alloc). If a class instance of 4000 bytes
//  or more were such an allocation, storing it into a field while the markers
//  have not reached it would mark it without ever tracing its fields, and the
//  young objects only it references would be freed.
//
// The instance (BigNode, 520 pointer fields, more than 4000 bytes) is made
//  outside any cycle in a frame of its own, with fresh young nodes in three of
//  its fields (first, middle, last) that nothing else references. Only its
//  scrambled address is kept while a cycle starts. Once the cycle is seen
//  running it is stored into a holder (barrier on the big instance), and a
//  fresh node is stored into one of its fields (barrier on the young node).
//  A big instance from an earlier round, already old, also gets a pre-cycle
//  young node stored into its last field during the cycle. After forced full
//  collections and churn that reuses freed memory, every field must still
//  hold its node with the right value.
//
// The test also reports how the big instance was allocated: a size field of 0
//  means a large allocation (AllocLarge), a non zero size with the container
//  bit means an Immix block object. Generated classes allocate through the
//  inline ImmixAllocator::alloc (include/hx/GC.h), which never goes to
//  AllocLarge, so the expected answer is "block objects": the barrier takes
//  its small object path (promote, then pushReferrer).
//
// The hidden objects are unreachable, so any reclaim before the barrier may
//  free them legitimately: a stop-the-world minor, or a whole cycle run
//  inside one allocation (an allocation near the heap bound waits for the
//  cycle), or the publish pause of the previous cycle. Such rounds are
//  detected and skipped, and the memory of the instance is checked intact
//  before it is used.

class BigFields {
   #if macro
   public static macro function build(count:Int):Array<Field> {
      var fields = Context.getBuildFields();
      var pos = Context.currentPos();
      for (i in 0...count) {
         fields.push({
            name: 'f$i',
            access: [APublic],
            kind: FVar(macro :Node, null),
            pos: pos
         });
      }
      return fields;
   }
   #end
}

#if !macro
class Node {
   public var value:Int;
   public var next:Node;
   public function new(v:Int) {
      value = v;
   }
}

@:build(BigFields.build(520))
class BigNode {
   public var id:Int;
   public function new(id:Int) {
      this.id = id;
   }
}

class Holder {
   public var big:BigNode;
   public function new() {}
}

class LargeObjectShade {
   static function makeTree(depth:Int, v:Int):Node {
      var n = new Node(v);
      if (depth > 0) {
         n.next = makeTree(depth - 1, v * 2);
         var other = makeTree(depth - 1, v * 2 + 1);
         if (other.value < 0) n.next = other;
      }
      return n;
   }

   static var keepTrees:Array<Array<Node>> = [];

   static function makeRetained() {
      // A retained heap, so that a marking cycle lasts long enough
      for (i in 0...24) {
         var list = [];
         for (j in 0...2000) {
            var n = new Node(j);
            n.next = new Node(j + 1);
            list.push(n);
         }
         keepTrees.push(list);
      }
   }

   static inline function markActive():Bool {
      return untyped __cpp__("(::hx::gConcurrentGcMarkActive != 0)");
   }

   static function header(b:BigNode):Int {
      return untyped __cpp__("(int)(((unsigned int *)({0}.mPtr))[-1])", b);
   }

   static function objectSize(b:BigNode):Int {
      return untyped __cpp__("(int)sizeof(BigNode_obj)");
   }

   static function hide(b:BigNode):cpp.Int64 {
      return untyped __cpp__("(cpp::Int64)(((size_t){0}.mPtr) ^ (size_t)0x5a5a5a5a5a5aULL)", b);
   }

   static function unhide(h:cpp.Int64):BigNode {
      return untyped __cpp__("::hx::ObjectPtr<BigNode_obj>((BigNode_obj *)(size_t)(((size_t){0}) ^ (size_t)0x5a5a5a5a5a5aULL))", h);
   }

   static function hideNode(n:Node):cpp.Int64 {
      return untyped __cpp__("(cpp::Int64)(((size_t){0}.mPtr) ^ (size_t)0x5a5a5a5a5a5aULL)", n);
   }

   static function unhideNode(h:cpp.Int64):Node {
      return untyped __cpp__("::hx::ObjectPtr<Node_obj>((Node_obj *)(size_t)(((size_t){0}) ^ (size_t)0x5a5a5a5a5a5aULL))", h);
   }

   // A cycle is active from its start to the end of its publish pause. The
   //  publish pause reclaims the lines of the objects it finds dead, so the
   //  hidden objects are made only after it
   static function cycleActive():Bool {
      return markActive() || Gc.memInfo64(104) != 0;
   }

   static var lastHeader:Int = 0;

   // Non zero words of the instance after its vtable pointer:
   //  4 for the id and the three nodes made with it
   static function nonZeroWords(b:BigNode):Int {
      return untyped __cpp__("([&]{ size_t *p = (size_t *){0}.mPtr; int n = 0; for(int i=1;i<(int)(sizeof(BigNode_obj)/8);i++) if (p[i]) n++; return n; })()", b);
   }

   // Stop-the-world minor and full collections so far: such a collection
   //  frees the hidden objects (nothing references them), so a round where
   //  one ran before the cycle started must not use them
   static function pauses():Float {
      return Gc.memInfo64(107) + Gc.memInfo64(115);
   }

   // Makes the big instance and its young nodes in a frame of its own and
   //  gives only the scrambled address of the instance, so that no stack slot
   //  of the caller still points to it or to its nodes
   @:noCompletion static function makeHidden(round:Int):cpp.Int64 {
      var big = new BigNode(round);
      big.f0 = new Node(round * 10 + 1);
      big.f260 = new Node(round * 10 + 2);
      big.f519 = new Node(round * 10 + 3);
      lastHeader = header(big);
      return hide(big);
   }

   @:noCompletion static function makeHiddenNode(v:Int):cpp.Int64 {
      return hideNode(new Node(v));
   }

   // Called through function values: the C++ compiler cannot inline them
   //  into main, where the objects would stay in a register or a stack slot
   //  that the conservative stack scan finds (the markers then mark them
   //  before the barrier meets them, and the test is not exercised)
   static var hiddenMaker:(Int) -> cpp.Int64 = makeHidden;
   static var hiddenNodeMaker:(Int) -> cpp.Int64 = makeHiddenNode;

   // Overwrites the stack area the calls above used
   static function scrub():Int {
      var a = [for (i in 0...64) i];
      return a[63];
   }

   static var sink:Array<Dynamic> = [];

   static function churn() {
      // small garbage, one allocation per call
      sink[0] = [1, 2, 3, 4];
   }

   static function check(holders:Array<Holder>, rounds:Array<Int>, last:Array<Int>):Int {
      var bad = 0;
      for (i in 0...holders.length) {
         var b = holders[i].big;
         var r = rounds[i];
         if (b.id != r) { bad++; continue; }
         if (b.f0 == null || b.f0.value != r * 10 + 1) bad++;
         if (b.f260 == null || b.f260.value != r * 10 + 4) bad++;
         if (b.f519 == null || b.f519.value != last[i]) bad++;
      }
      return bad;
   }

   static function main() {
      var rounds = 300;
      var args = Sys.args();
      if (args.length > 0) rounds = Std.parseInt(args[0]);

      makeRetained();

      var holders:Array<Holder> = [];
      var holderRounds:Array<Int> = [];
      var holderLast:Array<Int> = [];
      var hits = 0;
      var oldHits = 0;
      var cycles = 0;
      var largeAllocs = 0;
      var blockObjects = 0;
      var skipped = 0;
      var minorSkipped = 0;
      var reused = 0;
      for (round in 0...rounds) {
         // Out of any cycle (sweep and publish included), so that the instance
         //  is a pre-cycle nursery alloc that no reclaim can meet before the
         //  barrier
         var guard = 0;
         while (cycleActive() && guard++ < 50000000) churn();
         if (cycleActive()) { skipped++; continue; }
         var pausesBefore = pauses();
         var cyclesBefore = Gc.memInfo64(100);
         // Made on a short-lived thread: in an optimized build without stack
         //  frames, main kept a stale pointer to the instance in a register or
         //  stack slot, the conservative scan found it at the cycle start and
         //  the barrier never met it unmarked (0 hits). A thread that has
         //  exited has no stack to scan.
         var hidden:cpp.Int64 = 0;
         var hiddenYoung:cpp.Int64 = 0;
         var done = new sys.thread.Lock();
         sys.thread.Thread.create(() -> {
            hidden = hiddenMaker(round);
            hiddenYoung = hiddenNodeMaker(round * 10 + 5);
            done.release();
         });
         done.wait();
         Sys.sleep(0.001); // let the thread exit and unregister
         var h = lastHeader;
         if ((h & 0xff000000) != 0) {
            // allocated black or already promoted: not the case under test
            skipped++;
            continue;
         }
         if ((h & 0xffff) == 0) largeAllocs++;
         else if ((h & 0x00800000) != 0) blockObjects++;
         scrub();

         // Wait for a cycle to start. Every collection request starts a
         //  cycle with a low trigger ratio (run with
         //  HXCPP_GC_CONCURRENT_TRIGGER=0.15), mostly without a minor; the
         //  rounds where a reclaim may have freed the hidden objects are
         //  detected below and skipped.
         guard = 0;
         var started = false;
         while (guard++ < 20000000) {
            churn();
            if (markActive()) {
               started = true;
               break;
            }
         }
         if (!started) { skipped++; continue; }
         if (pauses() != pausesBefore || Gc.memInfo64(100) != cyclesBefore) {
            // A stop-the-world minor ran, or a whole cycle ran inside one
            //  allocation (an allocation near the heap bound waits for the
            //  cycle): either one rightly reclaimed the hidden objects
            minorSkipped++;
            continue;
         }
         cycles++;

         var big = unhide(hidden);
         if (nonZeroWords(big) != 4) {
            // the memory of the hidden instance was reused before the cycle:
            //  a reclaim the counters above did not see (test guard)
            reused++;
            big = null;
            continue;
         }
         var before = header(big);
         var holder = new Holder();
         holder.big = big; // write barrier on the big instance
         if ((before & 0xff000000) == 0) hits++;
         // write barrier on a fresh young node stored into the big instance,
         //  replacing its pre-cycle node (no other reference to the new one)
         big.f260 = new Node(round * 10 + 4);
         // write barrier on a pre-cycle young node stored into an old big
         //  instance of an earlier round
         if (holders.length > 0) {
            var young = unhideNode(hiddenYoung);
            var old = holders[holders.length - 1];
            if ((untyped __cpp__("(int)(((unsigned int *)({0}.mPtr))[-1])", young) & 0xff000000) == 0) oldHits++;
            old.big.f519 = young;
            holderLast[holderLast.length - 1] = round * 10 + 5;
         }
         big = null;
         holders.push(holder);
         holderRounds.push(round);
         holderLast.push(round * 10 + 3);
      }

      // Churn so that freed rows get reused before the check
      for (k in 0...3) {
         for (i in 0...200000) churn();
         Gc.run(true);
      }
      var bad = check(holders, holderRounds, holderLast);
      for (i in 0...200000) churn();
      Gc.run(true);
      bad += check(holders, holderRounds, holderLast);

      Sys.println('BigNode size=${objectSize(null)} bytes, block objects=$blockObjects large allocs=$largeAllocs');
      Sys.println('cycles=$cycles skipped=$skipped skipped after a reclaim=$minorSkipped reused before the cycle=$reused barrier hits on unmarked big instances=$hits on pre-cycle nodes into old big instances=$oldHits bad fields=$bad');
      if (bad > 0) { Sys.println("LARGE OBJECT SHADE FAILED"); Sys.exit(1); }
      else if (reused > 0) { Sys.println("LARGE OBJECT SHADE INVALID ROUNDS"); Sys.exit(1); }
      // A run that never met the case tests nothing: fail it
      else if (hits == 0) { Sys.println("LARGE OBJECT SHADE NOT EXERCISED"); Sys.exit(1); }
      else Sys.println("LARGE OBJECT SHADE OK");
   }
}
#end
