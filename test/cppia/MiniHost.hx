class MiniHost {
    public static function main() {
        var args = Sys.args();
        if (args.length == 0) {
            Sys.println('usage: MiniHost <file.cppia>');
            Sys.exit(1);
        }
        var source = sys.io.File.getBytes(args[0]);
        var module = cpp.cppia.Module.fromData(source.getData());
        module.boot();
        module.run();
    }
}
