import cpp.vm.Gc;
import RaceCommon.Val;

// Haxe finalizers run by the final remark of a concurrent cycle.
//
// The remark runs on the coordinator thread of the collector. A finalizer
//  must not allocate, with any collector (the classic one stops with "Bad
//  Allocation while collecting"), so this one only counts.
//
// Resources with a finalizer are kept in a sliding window, so that they are
//  promoted before they die: a young dead object is finalized by a minor
//  collection, on the mutator thread, which is not the case under test.

class Res {
   public var id:Int;
   public var data:Array<Int>;

   public function new(id:Int) {
      this.id = id;
      data = [id];
   }
}

class ReproFinalizer {
   static var finalizedCount = 0;

   static function onFinalize(r:Res):Void {
      finalizedCount++;
   }

   static function main() {
      var seconds = RaceCommon.seconds(30);
      var window:Array<Res> = [];
      var next = 0;
      RaceCommon.start();
      var start = Sys.time();
      var rounds = 0;
      while (Sys.time() - start < seconds) {
         for (i in 0...200) {
            var r = new Res(next++);
            Gc.setFinalizer(r, cpp.Function.fromStaticFunction(onFinalize));
            window.push(r);
         }
         if (window.length > 40000)
            window.splice(0, 20000);
         RaceCommon.churn(64);
         rounds++;
      }
      Sys.println('ReproFinalizer: $finalizedCount finalizers ran');
      // The resources that died since the last collection are still pending
      if (finalizedCount < next / 2)
         RaceCommon.fail('ReproFinalizer', 'only $finalizedCount finalizers ran for $next resources');
      RaceCommon.finish('ReproFinalizer', rounds);
   }
}
