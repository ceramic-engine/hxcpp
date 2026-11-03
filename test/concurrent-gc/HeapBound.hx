import cpp.vm.Gc;

// The heap must stop growing in a steady state, and come back down after a
// burst.
//
// 1. A persistent world with steady mutation (old garbage, so concurrent
//    cycles keep coming) and a high rate of short-lived frame data, like a UI
//    frame. With the unbounded concurrent collector every cycle started on an
//    empty free list and allocated all of its new objects into new blocks, so
//    the heap grew for as long as the program ran (GPUI port bench: about
//    820 MB for 50 MB live after 30 minutes, still growing).
// 2. A large structure is built, then dies: the heap must give back most of
//    what it grew for it (empty block groups above 1.5 times the goal).
//
// Built with -D HXCPP_GC_CONCURRENT_HEAP_MARGIN_MB=32 (run.sh), so that the
// goal binds within the run.
//
// Usage: HeapBound [frames] [world]
class Node {
   public var a:Node;
   public var b:Node;
   public var value:Int;
   public var label:String;

   public function new(value:Int) {
      this.value = value;
      label = "n" + (value & 1023);
   }
}

class HeapBound {
   static var seed = 12345;
   static var checksum = 0;
   static var burst:Array<Array<Node>> = [];

   static function burstStep() {
      burst.push([for (k in 0...40000) new Node(k)]);
   }

   // One frame: replace part of the world (old garbage, write barriers into
   //  old objects) and build a few MB of frame data that dies at the end
   static function frame(world:Array<Node>) {
      var worldSize = world.length;
      for (k in 0...1500) {
         seed = (seed * 1103515245 + 12345) & 0x7fffffff;
         var idx = seed % worldSize;
         world[idx] = new Node(seed);
         world[(idx + 1) % worldSize].label = "m" + (seed & 1023);
      }
      var head:Node = null;
      for (k in 0...30000) {
         var node = new Node(k);
         node.b = head;
         head = node;
      }
      var n = head;
      while (n != null) {
         checksum += n.value & 1;
         n = n.b;
      }
   }

   static function main() {
      var args = Sys.args();
      var frames = args.length > 0 ? Std.parseInt(args[0]) : 9000;
      var worldSize = args.length > 1 ? Std.parseInt(args[1]) : 150000;
      var world = [for (i in 0...worldSize) new Node(i)];
      for (i in 0...worldSize)
         world[i].a = world[(i * 31 + 7) % worldSize];
      var mb = (v:Float) -> Std.int(v / 1024 / 1024);
      var reserved = () -> Gc.memInfo64(Gc.MEM_INFO_RESERVED);

      // 1. Steady state: the heap must stop growing
      var reservedThird = 0.0;
      var reservedMax = 0.0;
      for (f in 0...frames) {
         frame(world);
         if (f >= frames / 3 && reserved() > reservedMax)
            reservedMax = reserved();
         if (f == Std.int(frames / 3))
            reservedThird = reserved();
      }
      // The heap stays within its goal (memInfo 121) and the slack a cycle
      //  may use (a quarter of the goal)
      var steadyGoal = Gc.memInfo64(121);
      var steadyOk = steadyGoal > 0 && reservedMax <= steadyGoal * 1.25 + 16 * 1024 * 1024;
      Sys.println('steady: reserved at a third ${mb(reservedThird)}MB, max after ${mb(reservedMax)}MB (goal ${mb(steadyGoal)}MB), cycles=${Gc.memInfo64(100)}, waits=${Gc.memInfo64(122)}');

      // 2. A burst: a large structure lives for a while, then dies; the
      //  heap must come back near its steady size
      // (like loading a level: the world is not mutated meanwhile, so the
      //  burst does not share its blocks with long lived objects; the heap
      //  does not move objects, it can only give back whole empty groups)
      for (i in 0...150)
         burstStep();
      var reservedBurst = reserved();
      // Held by a static only (a precise root), so it really dies here
      burst = null;
      for (f in 0...Std.int(frames / 2))
         frame(world);
      var reservedAfter = reserved();
      // The heap gives back its empty block groups above 1.5 times its goal
      //  (memInfo 121); groups that still hold a few objects stay (the heap
      //  does not move objects), hence the margin up to twice the goal
      var goal = Gc.memInfo64(121);
      var releaseOk = goal > 0 && reservedAfter <= goal * 2 + 16 * 1024 * 1024 && Gc.memInfo64(123) > 0;
      Sys.println('burst: reserved ${mb(reservedBurst)}MB during, ${mb(reservedAfter)}MB after (goal ${mb(goal)}MB), released ${mb(Gc.memInfo64(123))}MB, checksum=$checksum');

      Sys.println(steadyOk ? "heap bound: ok" : "heap bound: FAILED (the heap kept growing)");
      Sys.println(releaseOk ? "heap release: ok" : "heap release: FAILED (the heap stayed at its burst size)");
      if (!steadyOk || !releaseOk)
         Sys.exit(1);
   }
}
