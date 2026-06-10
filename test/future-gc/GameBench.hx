import cpp.vm.Gc;

// Game-style benchmark: large persistent world + heavy per-frame short-lived
// allocation + steady pointer mutation.  Reports frame time distribution.
class Entity {
   public var x:Float;
   public var y:Float;
   public var name:String;
   public var inventory:Array<Item>;
   public var target:Entity;

   public function new(i:Int) {
      x = i * 0.5;
      y = i * 0.25;
      name = "entity_" + (i & 8191);
      inventory = [for (k in 0...4) new Item(i + k)];
      target = null;
   }
}

class Item {
   public var kind:Int;
   public var label:String;
   public function new(k:Int) {
      kind = k;
      label = "item" + (k & 255);
   }
}

class Particle {
   public var x:Float;
   public var y:Float;
   public var vx:Float;
   public var vy:Float;
   public var next:Particle;
   public function new() {}
}

class GameBench {
   static var WORLD = 150000;
   static var FRAMES = 2000;
   static var PARTICLES_PER_FRAME = 2000;

   static function main() {
      var args = Sys.args();
      if (args.length > 0) FRAMES = Std.parseInt(args[0]);
      if (args.length > 1) WORLD = Std.parseInt(args[1]);

      // Build persistent world
      var world = [for (i in 0...WORLD) new Entity(i)];
      // entity graph links
      for (i in 0...WORLD)
         world[i].target = world[(i * 31 + 7) % WORLD];

      var grid = new Map<Int, Array<Entity>>();
      for (i in 0...WORLD) {
         var cell = i % 512;
         if (!grid.exists(cell)) grid.set(cell, []);
         grid.get(cell).push(world[i]);
      }

      Gc.run(true); // settle before measuring
      Sys.println('world ready, mem=${Std.int(Gc.memInfo64(Gc.MEM_INFO_USAGE)/1024/1024)}MB');

      var frameTimes = new Array<Float>();
      frameTimes.resize(FRAMES);

      var rng = 8675309;
      var particles:Particle = null;
      var events = new Array<{frame:Int, msg:String}>();

      var tStart = haxe.Timer.stamp();
      for (frame in 0...FRAMES) {
         var f0 = haxe.Timer.stamp();

         // particle churn (short-lived chains)
         var head:Particle = null;
         for (p in 0...PARTICLES_PER_FRAME) {
            var pa = new Particle();
            pa.x = p; pa.y = frame; pa.vx = 0.1; pa.vy = -0.1;
            pa.next = head;
            head = pa;
         }
         particles = head; // survives exactly one frame

         // event strings (short-lived)
         events.resize(0);
         for (e in 0...100)
            events.push({frame: frame, msg: 'evt$frame:$e'});

         // world mutation: retarget + inventory churn + grid moves
         for (m in 0...3000) {
            rng = rng * 1103515245 + 12345;
            var i = ((rng >> 8) & 0x7fffffff) % WORLD;
            var e = world[i];
            e.target = world[((rng >> 4) & 0x7fffffff) % WORLD];
            e.x += 0.01;
            if (m % 10 == 0)
               e.inventory[((rng >> 16) & 3)] = new Item(rng & 0xffff);
            if (m % 50 == 0) {
               // move between grid cells (array remove + push)
               var from = grid.get(i % 512);
               from.remove(e);
               grid.get((i * 7) % 512).push(e);
            }
         }

         // occasional bigger allocation (level chunk)
         if (frame % 64 == 0) {
            var chunk = [for (k in 0...5000) new Item(k + frame)];
            if (chunk.length != 5000) throw "bad";
         }

         frameTimes[frame] = (haxe.Timer.stamp() - f0) * 1000.0;
         #if HXCPP_TRACY
         cpp.vm.tracy.TracyProfiler.frameMark();
         #end
      }
      var total = haxe.Timer.stamp() - tStart;

      // verify world integrity
      for (i in 0...WORLD) {
         var e = world[i];
         if (e.name != "entity_" + (i & 8191)) throw 'corrupt entity $i';
         if (e.inventory.length != 4) throw 'corrupt inventory $i';
         if (e.target == null) throw 'lost target $i';
      }

      frameTimes.sort(Reflect.compare);
      var p50 = frameTimes[Std.int(FRAMES * 0.50)];
      var p95 = frameTimes[Std.int(FRAMES * 0.95)];
      var p99 = frameTimes[Std.int(FRAMES * 0.99)];
      var p999 = frameTimes[Std.int(FRAMES * 0.999)];
      var max = frameTimes[FRAMES - 1];

      Sys.println('frames=$FRAMES world=$WORLD total=${round2(total)}s avg=${round2(total*1000/FRAMES)}ms/frame');
      Sys.println('frame ms: p50=${round2(p50)} p95=${round2(p95)} p99=${round2(p99)} p99.9=${round2(p999)} max=${round2(max)}');
      Sys.println('mem=${Std.int(Gc.memInfo64(Gc.MEM_INFO_USAGE)/1024/1024)}MB reserved=${Std.int(Gc.memInfo64(Gc.MEM_INFO_RESERVED)/1024/1024)}MB');
      var cycles = Gc.memInfo64(100);
      if (cycles > 0)
         Sys.println('future cycles=$cycles lastRemark=${round2(Gc.memInfo64(101))}ms maxRemark=${round2(Gc.memInfo64(102))}ms');
      Sys.println("BENCH OK");
   }

   static function round2(f:Float):Float
      return Math.round(f * 1000) / 1000;
}
