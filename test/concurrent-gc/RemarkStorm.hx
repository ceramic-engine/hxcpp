import cpp.vm.Gc;

// Floods the remark pause with bulk-dirtied arrays while a concurrent cycle
// is running - exercises the budgeted-remark retry path.
class Obj {
   public var id:Int;
   public var pad:String;
   public function new(i:Int) { id = i; pad = "p" + (i & 255); }
}

class RemarkStorm {
   static function main() {
      // lots of decent-sized pointer arrays
      var arrays = [for (a in 0...6000) [for (i in 0...400) new Obj(a * 1000 + i)]];
      var churn:Array<Obj> = [];

      var stormed = 0;
      for (iter in 0...300) {
         // allocation pressure to drive cycles
         for (i in 0...500)
            churn.push(new Obj(i));
         churn.resize(0);

         // while a cycle is marking, bulk-dirty everything repeatedly
         if (Gc.memInfo64(104) == 1.0 && stormed < 12) {
            stormed++;
            for (a in arrays)
               a.reverse();
         }
      }

      // verify
      var sum = 0;
      for (a in 0...6000) {
         var arr = arrays[a];
         if (arr.length != 400) throw 'bad length $a';
         for (o in arr) {
            if (o.pad != "p" + (o.id & 255)) throw 'corrupt obj ${o.id}';
            sum += o.id;
         }
      }
      Gc.run(true);
      for (a in 0...6000)
         for (o in arrays[a])
            if (o.pad != "p" + (o.id & 255)) throw 'corrupt after full ${o.id}';

      Sys.println('stormed=$stormed cycles=${Gc.memInfo64(100)} maxRemark=${Gc.memInfo64(102)}ms sum=$sum');
      Sys.println("STORM OK");
   }
}
