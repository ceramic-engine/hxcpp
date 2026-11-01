/**
 * A string built at run time must hash like the equal string literal: the
 * compiler writes the hash of a literal over its UTF-8 bytes, and the run
 * time hash of a UTF-16 string must treat a surrogate pair as one code point.
 * Before the fix, a StringMap keyed by an emoji literal missed lookups with
 * an equal string built by substr, fromCharCode or StringBuf.
 */
class Main {
	static function check(lit:String, built:String, label:String) {
		final a = new Map<String, Int>();
		a.set(lit, 1);
		final b = new Map<String, Int>();
		b.set(built, 2);
		Sys.println('$label ${lit == built} ${a.get(built)} ${b.get(lit)}');
	}

	static function main() {
		final surrounding = "👩‍💻 suffix";
		check("👩‍💻", surrounding.substr(0, surrounding.length - " suffix".length), "zwj");
		check("😀", String.fromCharCode(0x1F600), "fromCharCode");
		check("é😀ab", "xé😀abx".substr(1, 5), "mixed");
		check("日本語", "前日本語".substr(1), "bmp");
		final buf = new StringBuf();
		buf.add("😀");
		buf.add("x");
		check("😀x", buf.toString(), "stringbuf");
	}
}
