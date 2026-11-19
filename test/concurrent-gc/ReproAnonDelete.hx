import RaceCommon.Val;

// Reflect.deleteField on the fixed fields of anonymous objects while a
//  concurrent cycle marks them.
//
// Anon_obj::__Remove shifts the fixed fields down, reading one entry past the
//  end of the allocation on its last step, and decrements the field count
//  only after the shift. A marker scanning the object meanwhile can read that
//  entry (bytes of the next object), or miss a value that moved from a slot
//  it had not scanned yet to a slot it had already scanned. The values are
//  referenced only by their anonymous object: a missed value is freed, and
//  the check of its content fails once its memory is reused.

class ReproAnonDelete {
   static var NAMES = ["a", "b", "c", "d", "e", "f", "g", "h"];

   static function make(slot:Int, gen:Int):Dynamic {
      return {
         a: new Val(slot, 0, gen), b: new Val(slot, 1, gen), c: new Val(slot, 2, gen), d: new Val(slot, 3, gen),
         e: new Val(slot, 4, gen), f: new Val(slot, 5, gen), g: new Val(slot, 6, gen), h: new Val(slot, 7, gen)
      };
   }

   static function checkObject(objs:Array<Dynamic>, masks:Array<Int>, gens:Array<Int>, i:Int) {
      var o = objs[i];
      for (k in 0...8) {
         if (masks[i] & (1 << k) != 0) {
            var raw:Dynamic = Reflect.field(o, NAMES[k]);
            if (!Std.isOfType(raw, Val))
               RaceCommon.fail('ReproAnonDelete', 'object $i field ${NAMES[k]} holds ${Type.typeof(raw)} (fields ' + Reflect.fields(o).join(',') + ', mask ${masks[i]})');
            var v:Val = raw;
            if (!v.check(i, k, gens[i]))
               RaceCommon.fail('ReproAnonDelete', 'object $i field ${NAMES[k]} corrupted: ${v.slot} ${v.key} ${v.gen}, expected gen ${gens[i]} (fields ' + Reflect.fields(o).join(',') + ')');
         }
      }
   }

   static function main() {
      var seconds = RaceCommon.seconds(30);
      var count = 50000;
      var objs:Array<Dynamic> = [];
      var masks:Array<Int> = [];
      var gens:Array<Int> = [];
      for (i in 0...count) {
         objs.push(make(i, 0));
         masks.push(0xff);
         gens.push(0);
      }
      RaceCommon.start();
      var start = Sys.time();
      var rounds = 0;
      while (Sys.time() - start < seconds) {
         for (i in 0...count) {
            var r = RaceCommon.rand();
            if (r & 1 == 0)
               continue;
            var m = masks[i];
            var k = (r >> 1) % 8;
            while (m & (1 << k) == 0)
               k = (k + 1) % 8;
            Reflect.deleteField(objs[i], NAMES[k]);
            m &= ~(1 << k);
            masks[i] = m;
            // Fewer than 2 fields left: start again with a new object
            if (m & (m - 1) == 0) {
               gens[i]++;
               objs[i] = make(i, gens[i]);
               masks[i] = 0xff;
            }
         }
         for (n in 0...2000)
            checkObject(objs, masks, gens, RaceCommon.rand() % count);
         RaceCommon.churn(64);
         rounds++;
      }
      for (i in 0...count)
         checkObject(objs, masks, gens, i);
      RaceCommon.finish('ReproAnonDelete', rounds);
   }
}
