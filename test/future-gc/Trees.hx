import cpp.vm.Gc;

// Classic binary-trees GC throughput benchmark
class TreeNode {
   public var left:TreeNode;
   public var right:TreeNode;
   public function new(l:TreeNode, r:TreeNode) {
      left = l;
      right = r;
   }
   public static function make(depth:Int):TreeNode {
      if (depth <= 0)
         return new TreeNode(null, null);
      return new TreeNode(make(depth - 1), make(depth - 1));
   }
   public function check():Int {
      if (left == null)
         return 1;
      return 1 + left.check() + right.check();
   }
}

class Trees {
   static function main() {
      var maxDepth = 19;
      if (Sys.args().length > 0)
         maxDepth = Std.parseInt(Sys.args()[0]);

      var t0 = haxe.Timer.stamp();

      var stretch = TreeNode.make(maxDepth + 1);
      Sys.println('stretch tree check: ${stretch.check()}');
      stretch = null;

      var longLived = TreeNode.make(maxDepth);

      var depth = 4;
      while (depth <= maxDepth) {
         var iterations = 1 << (maxDepth - depth + 4);
         var check = 0;
         for (i in 0...iterations)
            check += TreeNode.make(depth).check();
         Sys.println('$iterations trees of depth $depth check: $check');
         depth += 2;
      }

      Sys.println('long lived check: ${longLived.check()}');
      var dt = haxe.Timer.stamp() - t0;
      Sys.println('time: ${Math.round(dt*1000)}ms');
      Sys.println('mem=${Std.int(Gc.memInfo64(Gc.MEM_INFO_USAGE)/1024/1024)}MB cycles=${Gc.memInfo64(100)}');
      Sys.println("TREES OK");
   }
}
