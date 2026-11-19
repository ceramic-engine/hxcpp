import RaceCommon.Val;

// Arrays of objects that grow past the large allocation size (4000 bytes)
//  while a concurrent cycle marks them.
//
// ArrayBase::Realloc stores the new buffer pointer once InternalRealloc has
//  copied the elements, with no ordering between the copy and the store. A
//  large buffer can be a recycled allocation of the same size, still holding
//  the pointers of a dead array. With a weak memory order (ARM), a marker can
//  see the new buffer before the copied elements and follow those stale
//  pointers into freed memory.
//
// Each array is emptied (its buffer freed, so large buffers go back to the
//  recycle list) and filled again with new objects, so that recycled buffers
//  hold pointers to dead objects.

class ReproArrayGrow {
   static function main() {
      var seconds = RaceCommon.seconds(30);
      var count = 3000;
      var arrays:Array<Array<Val>> = [];
      var gens:Array<Int> = [];
      for (i in 0...count) {
         arrays.push([]);
         gens.push(0);
      }
      RaceCommon.start();
      var start = Sys.time();
      var rounds = 0;
      while (Sys.time() - start < seconds) {
         for (step in 0...200) {
            var i = RaceCommon.rand() % count;
            var a = arrays[i];
            cpp.NativeArray.setSize(a, 0);
            gens[i]++;
            var n = 600 + RaceCommon.rand() % 1500;
            for (j in 0...n)
               a.push(new Val(i, j, gens[i]));
         }
         for (n in 0...200) {
            var i = RaceCommon.rand() % count;
            var a = arrays[i];
            for (j in 0...a.length)
               if (!a[j].check(i, j, gens[i]))
                  RaceCommon.fail('ReproArrayGrow', 'array $i element $j corrupted');
         }
         RaceCommon.churn(64);
         rounds++;
      }
      RaceCommon.finish('ReproArrayGrow', rounds);
   }
}
