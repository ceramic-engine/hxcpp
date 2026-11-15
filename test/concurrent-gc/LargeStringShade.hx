import cpp.vm.Gc;

// Write barrier on a large UTF-16 string while a concurrent cycle marks.
//
// A large allocation made outside a cycle has a zero header except for the
//  flags that IMMIX_HEADER_PRESERVE keeps (a UTF-16 string has
//  HX_GC_STRING_CHAR16_T, a hashed one HX_GC_STRING_HASH). When such a string
//  is stored into a field while marking runs and the markers have not reached
//  it yet, ConcurrentGcShade must take it for what it is (a large nursery
//  allocation, size field 0) and not look it up as a small object of an
//  Immix block: that lookup reads a block id from the memory around the
//  string and crashed with a read of address 0x390 (null block info).
//
// The string is kept out of the markers' sight while the cycle starts (its
//  address is kept scrambled in an integer), then stored into a field as soon
//  as the cycle is seen running, so the barrier meets it unmarked.

class Node {
   public var left:Node;
   public var right:Node;
   public var value:Int;
   public function new(v:Int) {
      value = v;
   }
}

class Holder {
   public var text:String;
   public function new() {}
}

class LargeStringShade {
   static function makeTree(depth:Int, v:Int):Node {
      var n = new Node(v);
      if (depth > 0) {
         n.left = makeTree(depth - 1, v * 2);
         n.right = makeTree(depth - 1, v * 2 + 1);
      }
      return n;
   }

   static inline function markActive():Bool {
      return untyped __cpp__("(::hx::gConcurrentGcMarkActive != 0)");
   }

   static function makeLargeText(chars:Int, seed:Int):String {
      var buf = new StringBuf();
      buf.add(String.fromCharCode(0xe9)); // UTF-16 storage
      for (i in 1...chars)
         buf.addChar(97 + ((i + seed) % 26));
      return buf.toString();
   }

   static function header(s:String):Int {
      return untyped __cpp__("(int)(((unsigned int *){0}.raw_ptr())[-1])", s);
   }

   static function hide(s:String):cpp.Int64 {
      return untyped __cpp__("(cpp::Int64)(((size_t){0}.raw_ptr()) ^ (size_t)0x5a5a5a5a5a5aULL)", s);
   }

   static function unhide(h:cpp.Int64, length:Int):String {
      return untyped __cpp__("::String((const char16_t *)(size_t)(((size_t){0}) ^ (size_t)0x5a5a5a5a5a5aULL), {1})", h, length);
   }

   // Makes the string in a frame of its own and gives only its scrambled
   //  address (0 when the string is not a plain large nursery alloc), so
   //  that no stack slot of the caller still points to it
   @:noCompletion static function makeHidden(chars:Int, seed:Int):cpp.Int64 {
      var text = makeLargeText(chars, seed);
      if ((header(text) & 0xff00ffff) != 0) return 0;
      return hide(text);
   }

   // Called through a function value: the C++ compiler cannot inline it into
   //  main, where the string would stay in a register or a stack slot that the
   //  conservative stack scan finds (the markers then mark the string before
   //  the barrier meets it, and the test is not exercised)
   static var hiddenMaker:(Int, Int) -> cpp.Int64 = makeHidden;

   // Overwrites the stack area the call above used
   static function scrub():Int {
      var a = [for (i in 0...64) i];
      return a[63];
   }

   static var sink:Array<Dynamic> = [];

   static function churn() {
      // small garbage, one allocation per call
      sink[0] = [1, 2, 3, 4];
   }

   static function main() {
      var rounds = 300;
      var args = Sys.args();
      if (args.length > 0) rounds = Std.parseInt(args[0]);

      // A retained heap, so that a marking cycle lasts long enough
      var keep = [];
      for (i in 0...24) keep.push(makeTree(15, i));

      var holders = [];
      var hits = 0;
      var cycles = 0;
      var chars = 4000; // 8 kB of UTF-16: a large allocation
      for (round in 0...rounds) {
         // Out of any cycle, so that the string is a large nursery alloc
         var guard = 0;
         while (markActive() && guard++ < 50000000) churn();
         var hidden = hiddenMaker(chars, round);
         if (hidden == (0:cpp.Int64)) {
            // allocated black or already promoted: not the case under test
            continue;
         }
         scrub();

         // Wait for a cycle to start in one of these allocations. Every
         //  collection request starts a cycle with a low trigger ratio
         //  (run with HXCPP_GC_CONCURRENT_TRIGGER=0.15), so no minor can
         //  free the hidden string before the barrier meets it.
         guard = 0;
         var started = false;
         while (guard++ < 20000000) {
            churn();
            if (markActive()) {
               started = true;
               break;
            }
         }
         if (!started) continue;
         cycles++;

         var back = unhide(hidden, chars);
         var before = header(back);
         var holder = new Holder();
         holder.text = back; // write barrier: ConcurrentGcShade
         if ((before & 0xff000000) == 0 && (before & 0x00f00000) != 0) hits++;
         holders.push(holder);
         if (holders.length > 8) holders.shift();
      }

      Gc.run(true);
      for (i in 0...holders.length) {
         var t = holders[i].text;
         if (t.length != chars || t.charCodeAt(0) != 0xe9) throw 'bad text in holder $i';
      }
      Sys.println('cycles=$cycles barrier hits on unmarked large UTF-16 strings=$hits');
      // A run that never met the case tests nothing: fail it
      if (hits == 0) { Sys.println("LARGE STRING SHADE NOT EXERCISED"); Sys.exit(1); }
      else Sys.println("LARGE STRING SHADE OK");
   }
}
