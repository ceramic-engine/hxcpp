import cpp.vm.Gc;

// Shared helpers of the race reproduction tests (Repro*.hx)

class Val {
   public var slot:Int;
   public var key:Int;
   public var gen:Int;
   public var pad:Array<Int>;

   public function new(slot:Int, key:Int, gen:Int) {
      this.slot = slot;
      this.key = key;
      this.gen = gen;
      pad = [slot, key, gen];
   }

   // False when the object was freed and its memory reused
   public function check(slot:Int, key:Int, gen:Int):Bool {
      return this.slot == slot && this.key == key && this.gen == gen
         && pad != null && pad.length == 3 && pad[0] == slot && pad[1] == key && pad[2] == gen;
   }
}

class RaceCommon {
   public static var seed = 12345;

   // Park-Miller generator computed in doubles: an Int multiplication that
   //  overflows is undefined behaviour in the generated C++, and the optimizer
   //  then produced negative values despite the mask
   public static inline function rand():Int {
      seed = Std.int((seed * 16807.0) % 2147483647.0);
      return seed;
   }

   static var garbage:Array<Array<Int>> = [];

   // Garbage that keeps concurrent cycles running, part of it kept for a while
   public static function churn(count:Int) {
      for (k in 0...count)
         garbage.push([for (j in 0...32) j]);
      if (garbage.length > 20000)
         garbage = [];
   }

   public static var cyclesStart = 0.0;

   public static function start() {
      cyclesStart = Gc.memInfo64(100);
   }

   public static function finish(name:String, rounds:Int) {
      var cycles = Gc.memInfo64(100) - cyclesStart;
      if (cycles <= 0) {
         Sys.println('FAIL $name: no concurrent cycle ran ($rounds rounds)');
         Sys.exit(1);
      }
      Sys.println('$name: $rounds rounds, $cycles concurrent cycles');
      Sys.println('OK');
   }

   public static function fail(name:String, msg:String) {
      Sys.println('FAIL $name: $msg');
      Sys.exit(1);
   }

   public static function seconds(def:Float):Float {
      var args = Sys.args();
      return args.length > 0 ? Std.parseFloat(args[0]) : def;
   }
}
