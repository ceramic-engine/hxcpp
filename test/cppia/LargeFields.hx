import haxe.macro.Context;
import haxe.macro.Expr;

// Build macro for the large instance test: adds `count` fields `f0`, `f1`, ...
// of type `typeName` to the class, enough to make an instance larger than
// the GC large object threshold (4000 bytes).
class LargeFields
{
   public static macro function build(count:Int, typeName:String):Array<Field>
   {
      var fields = Context.getBuildFields();
      var type = TPath({ pack:[], name:typeName });
      for(i in 0...count)
         fields.push({ name:'f$i', access:[APublic], kind:FVar(type, null), pos:Context.currentPos() });
      return fields;
   }
}
