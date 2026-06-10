import cpp.vm.Gc;

// Pure short-lived allocation throughput (games: particles/events/temp)
class Tmp {
   public var a:Int;
   public var b:Float;
   public var c:Tmp;
   public function new(i:Int) { a = i; b = i * 0.5; c = null; }
}

class AllocRate {
   static function main() {
      var n = 30000000;
      if (Sys.args().length > 0)
         n = Std.parseInt(Sys.args()[0]);

      var t0 = haxe.Timer.stamp();
      var sink:Tmp = null;
      for (i in 0...n) {
         var t = new Tmp(i);
         t.c = sink;
         if ((i & 1023) == 0)
            sink = t; // keep ~0.1% alive briefly
         if ((i & 0xfffff) == 0)
            sink = null;
      }
      var dt = haxe.Timer.stamp() - t0;
      Sys.println('allocated $n objects in ${Math.round(dt*1000)}ms = ${Math.round(n/dt/1000000)}M allocs/sec');
      Sys.println('mem=${Std.int(Gc.memInfo64(Gc.MEM_INFO_USAGE)/1024/1024)}MB cycles=${Gc.memInfo64(100)}');
      Sys.println("ALLOC OK");
   }
}
