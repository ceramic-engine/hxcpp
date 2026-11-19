import RaceCommon.Val;

// Fields of anonymous objects that change type while a concurrent cycle marks
//  them.
//
// A field of an anonymous object is a cpp::Variant (a type and a value).
//  Variant::mark reads the type, then the value, while the mutator writes
//  both. A marker that reads the old type (object) with the new value (the
//  bits of a double) follows the double as a pointer.
//
// Each record has a Null<Float> field that switches between null and a
//  number, and a Dynamic field that switches between an object and a number.

typedef Rec = {
   var v:Null<Float>;
   var d:Dynamic;
}

class ReproVariantFlip {
   static function main() {
      var seconds = RaceCommon.seconds(30);
      var count = 50000;
      var pool = [for (i in 0...1000) new Val(i, 0, 0)];
      var recs:Array<Rec> = [];
      var states:Array<Bool> = [];
      for (i in 0...count) {
         recs.push({v: null, d: pool[i % 1000]});
         states.push(true);
      }
      RaceCommon.start();
      var start = Sys.time();
      var rounds = 0;
      while (Sys.time() - start < seconds) {
         for (i in 0...count) {
            var r = recs[i];
            if (states[i]) {
               r.v = i + 0.5;
               r.d = i * 2.0 + 0.25;
            }
            else {
               r.v = null;
               r.d = pool[i % 1000];
            }
            states[i] = !states[i];
         }
         RaceCommon.churn(64);
         rounds++;
      }
      for (i in 0...count) {
         var r = recs[i];
         if (states[i]) {
            var d:Val = r.d;
            if (r.v != null || d == null || !d.check(i % 1000, 0, 0))
               RaceCommon.fail('ReproVariantFlip', 'record $i has a wrong value');
         }
         else if (r.v != i + 0.5 || r.d != i * 2.0 + 0.25) {
            RaceCommon.fail('ReproVariantFlip', 'record $i has a wrong number');
         }
      }
      RaceCommon.finish('ReproVariantFlip', rounds);
   }
}
