// A class defined in a cppia script with enough fields to be larger than
// the GC large object threshold (4000 bytes). Its fields are the only
// references to fresh nodes; after collections and churn every node must
// still hold its values. The same is checked with a compiled host class.
class ScriptNode
{
   public var value:Int;
   public var check:Int;
   public function new(inValue:Int)
   {
      value = inValue;
      check = inValue ^ 0x5a5a5a;
   }
}

@:build(LargeFields.build(520, "ScriptNode"))
class ScriptBig
{
   public function new() { }
}

// Below the threshold, for comparison
@:build(LargeFields.build(400, "ScriptNode"))
class ScriptMid
{
   public function new() { }
}

class LargeInstanceClient
{
   static inline var ROUNDS = 40;
   static inline var PER_ROUND = 8;
   static var churnSink:Array<ScriptNode>;

   static function makeScript(id:Int):ScriptBig
   {
      var big = new ScriptBig();
      big.f0 = new ScriptNode(id * 1000);
      big.f260 = new ScriptNode(id * 1000 + 260);
      big.f519 = new ScriptNode(id * 1000 + 519);
      return big;
   }

   static function makeMid(id:Int):ScriptMid
   {
      var mid = new ScriptMid();
      mid.f0 = new ScriptNode(id * 1000);
      mid.f260 = new ScriptNode(id * 1000 + 260);
      mid.f399 = new ScriptNode(id * 1000 + 399);
      return mid;
   }

   static function makeHost(id:Int):LargeInstanceTypes.HostBig
   {
      var big = new LargeInstanceTypes.HostBig();
      big.f0 = new LargeInstanceTypes.HostNode(id * 1000);
      big.f260 = new LargeInstanceTypes.HostNode(id * 1000 + 260);
      big.f519 = new LargeInstanceTypes.HostNode(id * 1000 + 519);
      return big;
   }

   static function bad(value:Int, check:Int, expected:Int):Int
   {
      return (value == expected && check == (expected ^ 0x5a5a5a)) ? 0 : 1;
   }

   static function churn()
   {
      // Reuse the memory of anything the collector freed
      for(i in 0...20000)
         churnSink[i & 4095] = new ScriptNode(-1);
   }

   public static function main()
   {
      churnSink = [ for(i in 0...4096) null ];
      var scripts = new Array<ScriptBig>();
      var hosts = new Array<LargeInstanceTypes.HostBig>();
      var mids = new Array<ScriptMid>();
      var midBad = 0;
      var scriptBad = 0;
      var hostBad = 0;
      var checked = 0;
      var id = 0;
      for(round in 0...ROUNDS)
      {
         for(i in 0...PER_ROUND)
         {
            scripts.push(makeScript(id));
            hosts.push(makeHost(id));
            mids.push(makeMid(id));
            id++;
         }
         for(c in 0...3)
         {
            churn();
            cpp.vm.Gc.run(true);
         }
         churn();
         for(n in 0...id)
         {
            var s = scripts[n];
            scriptBad += bad(s.f0.value, s.f0.check, n * 1000)
                       + bad(s.f260.value, s.f260.check, n * 1000 + 260)
                       + bad(s.f519.value, s.f519.check, n * 1000 + 519);
            var h = hosts[n];
            hostBad += bad(h.f0.value, h.f0.check, n * 1000)
                     + bad(h.f260.value, h.f260.check, n * 1000 + 260)
                     + bad(h.f519.value, h.f519.check, n * 1000 + 519);
            var m = mids[n];
            midBad += bad(m.f0.value, m.f0.check, n * 1000)
                    + bad(m.f260.value, m.f260.check, n * 1000 + 260)
                    + bad(m.f399.value, m.f399.check, n * 1000 + 399);
            checked += 3;
         }
      }
      Sys.println('instances: $id of each class, $checked fields checked for each class');
      Sys.println('bad fields: large script class $scriptBad, large host class $hostBad, small script class $midBad');
      var ok = scriptBad == 0 && hostBad == 0 && midBad == 0;
      Sys.println(ok ? 'LARGE INSTANCE OK' : 'LARGE INSTANCE FAILED');
      if (!ok)
         Sys.exit(1);
   }
}
