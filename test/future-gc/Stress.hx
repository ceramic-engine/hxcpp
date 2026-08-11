import cpp.vm.Gc;
import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;

class GraphNode {
   public var id:Int;
   public var checksum:Int;
   public var children:Array<GraphNode>;
   public var tag:String;
   public var meta:Map<String, Int>;

   public function new(id:Int) {
      this.id = id;
      this.checksum = id * 0x9E3779B1;
      this.children = [];
      this.tag = "n" + id;
      this.meta = null;
   }

   public function verify():Int {
      if (checksum != id * 0x9E3779B1)
         throw 'corrupt node $id : $checksum';
      if (tag != "n" + id)
         throw 'corrupt tag on $id : $tag';
      var sum = 1;
      for (c in children)
         sum += c.verify();
      if (meta != null)
         for (k => v in meta)
            if ("m" + v != k)
               throw 'corrupt meta $k=$v on node $id';
      return sum;
   }
}

class Stress {
   static inline var THREADS = 6;
   static var ITERS = 400;

   static var sharedQueue:Deque<GraphNode> = new Deque();
   static var mutex = new Mutex();
   static var sharedRetained:Array<GraphNode> = [];
   static var errors:Array<String> = [];
   static var finishedCount = 0;

   static function buildGraph(rng:Int, depth:Int):GraphNode {
      var root = new GraphNode(rng);
      if (depth > 0) {
         var n = 1 + (rng % 3);
         for (i in 0...n)
            root.children.push(buildGraph(rng * 31 + i + 1, depth - 1));
      }
      if (rng % 7 == 0) {
         root.meta = new Map();
         for (i in 0...(rng % 24))
            root.meta.set("m" + (rng + i), rng + i);
      }
      return root;
   }

   static function workerMain(seed:Int) {
      try {
         var retained = new Array<GraphNode>();
         var weakMap = new haxe.ds.WeakMap<GraphNode, String>();
         var rng = seed;

         for (iter in 0...ITERS) {
            rng = rng * 1103515245 + 12345;
            var r = (rng >> 8) & 0xffff;

            // churn: short-lived graph, verified immediately
            var g = buildGraph(r + 1, 5);
            g.verify();

            // survivor graph
            var s = buildGraph(r + 2, 6);
            s.verify();
            retained.push(s);
            if (retained.length > 12)
               retained.shift(); // exercises RemoveElement memmove

            // bulk array ops on pointer arrays
            var arr = retained.copy();
            arr.reverse();
            arr.insert(0, g);
            arr.splice(0, 1);
            for (a in arr)
               a.verify();

            // string churn
            var sb = new StringBuf();
            for (i in 0...50)
               sb.add("part" + ((r + i) & 1023));
            if (sb.toString().length < 50)
               throw "bad stringbuf";

            // weak map entries (collected + surviving)
            if (iter % 8 == 0) {
               weakMap.set(s, s.tag);
               var w = weakMap.get(s);
               if (w != null && w != s.tag)
                  throw 'weak map corrupt: $w vs ${s.tag}';
            }

            // cross-thread sharing
            sharedQueue.add(s);
            var got = sharedQueue.pop(false);
            if (got != null)
               got.verify();

            mutex.acquire();
            sharedRetained.push(s);
            if (sharedRetained.length > 40)
               sharedRetained.reverse();
            if (sharedRetained.length > 50)
               sharedRetained.splice(0, 25);
            mutex.release();

            // verify retained periodically
            if (iter % 25 == 0) {
               for (k in retained)
                  k.verify();
               mutex.acquire();
               for (k in sharedRetained)
                  k.verify();
               mutex.release();
            }
         }
         for (k in retained)
            k.verify();
      } catch (e:Dynamic) {
         mutex.acquire();
         errors.push('worker $seed: $e');
         mutex.release();
      }
      mutex.acquire();
      finishedCount++;
      mutex.release();
   }

   static function main() {
      if (Sys.args().length > 0)
         ITERS = Std.parseInt(Sys.args()[0]);

      var t0 = haxe.Timer.stamp();

      for (t in 0...THREADS)
         Thread.create(() -> workerMain(t * 7919 + 17));

      // main thread churns too, and spawns short-lived threads
      var done = 0;
      var spawned = 0;
      var mainRng = 12345;
      while (done < THREADS) {
         mainRng = mainRng * 1103515245 + 12345;
         var g = buildGraph(((mainRng >> 8) & 0xffff) + 99, 4);
         g.verify();
         if (spawned < 40) {
            spawned++;
            var sd = spawned;
            Thread.create(() -> {
               var x = buildGraph(sd * 13 + 7, 5);
               x.verify();
            });
         }
         mutex.acquire();
         done = finishedCount;
         var err = errors.length > 0 ? errors[0] : null;
         mutex.release();
         if (err != null)
            throw err;
      }

      Sys.println('threads done in ${haxe.Timer.stamp() - t0}s');
      mutex.acquire();
      for (k in sharedRetained)
         k.verify();
      mutex.release();

      Gc.run(true);
      Gc.run(true);

      mutex.acquire();
      for (k in sharedRetained)
         k.verify();
      var errCount = errors.length;
      mutex.release();

      if (errCount > 0)
         throw errors[0];

      Sys.println('cycles=${Gc.memInfo(100)} lastRemark=${Gc.memInfo(101)}ms maxRemark=${Gc.memInfo(102)}ms');
      Sys.println("STRESS OK");
   }
}
