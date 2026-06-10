import cpp.vm.Gc;

class Node {
   public var left:Node;
   public var right:Node;
   public var value:Int;
   public var name:String;
   public function new(v:Int) {
      value = v;
      name = "node" + (v & 1023);
   }
}

class Smoke {
   static function makeTree(depth:Int, v:Int):Node {
      var n = new Node(v);
      if (depth > 0) {
         n.left = makeTree(depth - 1, v * 2);
         n.right = makeTree(depth - 1, v * 2 + 1);
      }
      return n;
   }

   static function checkTree(n:Node, depth:Int, v:Int):Int {
      if (n.value != v) throw 'bad value ${n.value} != $v';
      var sum = n.value;
      if (depth > 0) {
         sum += checkTree(n.left, depth - 1, v * 2);
         sum += checkTree(n.right, depth - 1, v * 2 + 1);
      }
      return sum;
   }

   static function main() {
      var keep = new Array<Node>();
      var maps = new Array<Map<String, Node>>();
      for (iter in 0...60) {
         // churn: short-lived trees
         for (i in 0...40) {
            var t = makeTree(8, 1);
            checkTree(t, 8, 1);
         }
         // some survivors
         var t = makeTree(10, 1);
         keep.push(t);
         if (keep.length > 8) keep.shift();

         var m = new Map<String, Node>();
         for (i in 0...500)
            m.set("key" + i, new Node(i));
         maps.push(m);
         if (maps.length > 4) maps.shift();

         // verify retained data
         for (k in keep) checkTree(k, 10, 1);
         for (m in maps)
            for (i in 0...500)
               if (m.get("key" + i).value != i) throw "bad map value";

         if (iter % 20 == 0)
            Sys.println('iter $iter mem=${Gc.memInfo(Gc.MEM_INFO_USAGE)}');
      }
      // explicit major
      Gc.run(true);
      for (k in keep) checkTree(k, 10, 1);
      Sys.println("SMOKE OK");
   }
}
