class VectorRepro {
    public static function main() {
        var vd = new haxe.ds.Vector<Dynamic>(2);
        vd.set(0, () -> 'hi');
        var f:Void->String = vd.get(0);
        trace('closure in vector: ' + f());
        var vi = new haxe.ds.Vector<Int>(3);
        vi.set(1, 42);
        trace('int in vector: ' + vi.get(1));
        var vs = new haxe.ds.Vector<String>(2);
        vs.set(0, 'str');
        trace('string in vector: ' + vs.get(0));
        trace('DONE');
    }
}
