// Host of the large instance test: a compiled class with as many fields as
// the script class, for comparison, and the cppia loader. Run with the
// .cppia file path, and `-jit` to use the cppia JIT.
class LargeInstanceHost
{
   public static function main()
   {
      var args = Sys.args();
      if (args.remove("-jit"))
         cpp.cppia.Host.enableJit(true);
      if (args.length == 0)
      {
         Sys.println('usage: LargeInstanceHost <file.cppia> [-jit]');
         Sys.exit(1);
      }
      // Keep the GC API in the host so the script can call it
      cpp.vm.Gc.run(false);
      var source = sys.io.File.getBytes(args[0]);
      var module = cpp.cppia.Module.fromData(source.getData());
      module.boot();
      module.run();
   }
}
