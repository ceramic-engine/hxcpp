import RaceCommon.Val;

// Insertions into large maps while a concurrent cycle marks them.
//
// Hash::set stores el->next = bucket[h], then bucket[h] = el, with no
//  ordering between the two stores. With a weak memory order (ARM), a marker
//  can see the new element in the bucket with a null next, and stop walking
//  the chain: the older elements behind it are not marked. Removals also
//  shrink the maps (Hash::compact), which moves chains before the map is
//  queued for a rescan.
//
// Each map holds a sliding window of keys: the oldest key is removed and a
//  new one inserted, so the chains hold old elements behind each new one. The
//  values are referenced only by their map.

class ReproHashInsert {
   static function main() {
      var seconds = RaceCommon.seconds(30);
      var mapCount = 32;
      var window = 30000;
      var maps:Array<haxe.ds.IntMap<Val>> = [];
      var los:Array<Int> = [];
      var his:Array<Int> = [];
      for (m in 0...mapCount) {
         var map = new haxe.ds.IntMap<Val>();
         for (k in 0...window)
            map.set(k, new Val(m, k, 0));
         maps.push(map);
         los.push(0);
         his.push(window);
      }
      RaceCommon.start();
      var start = Sys.time();
      var rounds = 0;
      while (Sys.time() - start < seconds) {
         for (step in 0...20000) {
            var m = RaceCommon.rand() % mapCount;
            var map = maps[m];
            map.remove(los[m]);
            los[m]++;
            map.set(his[m], new Val(m, his[m], 0));
            his[m]++;
         }
         // Now and then, shrink a map to half its size and grow it back
         if (rounds % 10 == 0) {
            var m = RaceCommon.rand() % mapCount;
            var map = maps[m];
            var half = los[m] + ((his[m] - los[m]) >> 1);
            for (k in los[m]...half)
               map.remove(k);
            for (k in los[m]...half)
               map.set(k, new Val(m, k, 0));
         }
         for (n in 0...2000) {
            var m = RaceCommon.rand() % mapCount;
            var lo = los[m];
            var span = his[m] - lo;
            var r = RaceCommon.rand();
            var k = lo + r % span;
            var v = maps[m].get(k);
            if (v == null || !v.check(m, k, 0))
               RaceCommon.fail('ReproHashInsert', 'map $m key $k lost or corrupted (lo $lo span $span r $r, window ${los[m]} to ${his[m]}, value ' + (v == null ? 'null' : '${v.slot} ${v.key} ${v.gen}') + ')');
         }
         RaceCommon.churn(64);
         rounds++;
      }
      for (m in 0...mapCount)
         for (k in los[m]...his[m]) {
            var v = maps[m].get(k);
            if (v == null || !v.check(m, k, 0))
               RaceCommon.fail('ReproHashInsert', 'map $m key $k lost or corrupted');
         }
      RaceCommon.finish('ReproHashInsert', rounds);
   }
}
