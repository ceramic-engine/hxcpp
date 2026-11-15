// Compiled host classes of the large instance test (see LargeInstanceClient).
class HostNode
{
   public var value:Int;
   public var check:Int;
   public function new(inValue:Int)
   {
      value = inValue;
      check = inValue ^ 0x5a5a5a;
   }
}

@:build(LargeFields.build(520, "HostNode"))
class HostBig
{
   public function new() { }
}
