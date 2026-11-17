import cpp.vm.Gc;

// Arrays resized by the mutator while a concurrent cycle marks them.
//
// ArrayBase::__SetSizeExact(0) releases the buffer and clears mBase, mAlloc
//  and length. Array_obj::__Mark reads mAlloc then mBase from the marker
//  threads, without synchronization. If a marker reads a non zero mAlloc and
//  then the cleared mBase, it marks a null allocation and reads its header
//  at address -4.
//
// The same race exists when an empty array (null buffer) gets its first
//  element: Realloc stores mBase then mAlloc, and with a weak memory order
//  (ARM) a marker may see the new mAlloc with the old null mBase.
//
// Many reachable Float arrays are emptied with __SetSizeExact(0), or replaced
//  by new empty arrays, and grown again in a loop, while garbage keeps concurrent cycles running, so that
//  the markers often visit an array in the middle of a resize. The test
//  fails if no concurrent cycle ran, and checks the content of the arrays.

class ArrayResizeRace {
   static function main() {
      var seconds = 20.0;
      var args = Sys.args();
      if (args.length > 0)
         seconds = Std.parseFloat(args[0]);

      var count = args.length > 1 ? Std.parseInt(args[1]) : 100000;
      var arrays:Array<Array<Float>> = [];
      for (i in 0...count)
         arrays.push([for (j in 0...8) j]);

      var garbage:Array<Array<Int>> = [];
      var cyclesStart = Gc.memInfo64(100);
      var start = Sys.time();
      var rounds = 0;
      var seed = 12345;

      while (Sys.time() - start < seconds) {
         for (i in 0...count) {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            var a = arrays[i];
            if (seed & 1 == 0) {
               cpp.NativeArray.setSize(a, 0);
            } else {
               a = new Array<Float>();
               arrays[i] = a;
            }
            var n = 1 + (seed % 24);
            for (j in 0...n)
               a.push(j + 0.5);
         }
         // Garbage to keep cycles running, part of it kept for a while
         for (k in 0...64)
            garbage.push([for (j in 0...32) j]);
         if (garbage.length > 20000)
            garbage = [];
         rounds++;
      }

      for (i in 0...count) {
         var a = arrays[i];
         for (j in 0...a.length) {
            if (a[j] != j + 0.5) {
               Sys.println('FAIL array $i element $j: ${a[j]}');
               Sys.exit(1);
            }
         }
      }

      var cycles = Gc.memInfo64(100) - cyclesStart;
      if (cycles <= 0) {
         Sys.println('FAIL no concurrent cycle ran ($rounds rounds)');
         Sys.exit(1);
      }
      Sys.println('ArrayResizeRace: $rounds rounds, $cycles concurrent cycles');
      Sys.println('OK');
   }
}
