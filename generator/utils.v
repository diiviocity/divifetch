// utils.v — pure helpers sitting between the parsers and the emitters:
// Text escapes for the zig and V sources that get generated, the lip-side
// unescape of what blip hands back, the terminal width of one line.
// the divifetch-zig generator.
module main

import os

// lip_unescape decodes the escapes blip's reader passes through untouched.
// its own table is n, t, r, 0, the quote and the backslash alone — but a
// config prefix lives and dies on ANSI, so the generator carries two more:
// \e is the escape byte, and \xHH one raw hex byte. a doubled backslash
// still yields a single backslash, spelled paths survive.
fn lip_unescape(s string) string {
	if !s.contains('\\') {
		return s
	}
	mut out := []u8{}
	mut i := 0
	for i < s.len {
		b := s[i]
		if b != u8(92) || i + 1 >= s.len {
			out << b
			i++
			continue
		}
		nb := s[i + 1]
		if nb == u8(92) {
			out << u8(92)
			i += 2
			continue
		}
		if nb == `e` {
			out << u8(27)
			i += 2
			continue
		}
		if nb == `x` {
			hi := hex_digit(s[i + 2]) or {
				out << b
				i++
				continue
			}
			if i + 3 >= s.len {
				out << b
				i++
				continue
			}
			lo := hex_digit(s[i + 3]) or {
				out << b
				i++
				continue
			}
			out << hi * u8(16) + lo
			i += 4
			continue
		}
		out << b
		i++
	}
	return out.bytestr()
}

// hex_digit reads one hex digit into its nibble.
fn hex_digit(b u8) ?u8 {
	match b {
		`0` { return u8(0) }
		`1` { return u8(1) }
		`2` { return u8(2) }
		`3` { return u8(3) }
		`4` { return u8(4) }
		`5` { return u8(5) }
		`6` { return u8(6) }
		`7` { return u8(7) }
		`8` { return u8(8) }
		`9` { return u8(9) }
		`a` { return u8(10) }
		`b` { return u8(11) }
		`c` { return u8(12) }
		`d` { return u8(13) }
		`e` { return u8(14) }
		`f` { return u8(15) }
		`A` { return u8(10) }
		`B` { return u8(11) }
		`C` { return u8(12) }
		`D` { return u8(13) }
		`E` { return u8(14) }
		`F` { return u8(15) }
		else { return none }
	}
}

// ─── art ──────────────────────────────────────────────────────────────────

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

// visible_width counts what a terminal shows for one line: runes are one
// column each, ANSI control sequences are none, art files holding the raw
// text spelling \033[ escape by that way too. bytes make a rune by their
// lead byte; the old generator counted runes this way.
fn visible_width(s string) int {
	mut width := 0
	mut i := 0
	for i < s.len {
		b := s[i]
		// an escape byte opens a CSI sequence up to its 0x40..0x7e tail.
		if b == u8(0x1b) && i + 1 < s.len && s[i + 1] == u8(0x5b) {
			i += 2
			for i < s.len && !(s[i] >= u8(0x40) && s[i] <= u8(0x7e)) {
				i++
			}
			if i < s.len { i++ }
			continue
		}
		// the raw \033[ text spelling: five bytes, then the same tail.
		if b == u8(0x5c) && i + 4 < s.len && s[i + 1] == u8(0x30) && s[i + 2] == u8(0x33) && s[i + 3] == u8(0x33) && s[i + 4] == u8(0x5b) {
			i += 5
			for i < s.len && !(s[i] >= u8(0x40) && s[i] <= u8(0x7e)) {
				i++
			}
			if i < s.len { i++ }
			continue
		}
		// one rune, one column: lead bytes walk their rune whole.
		if b >= u8(0xf0) {
			i += 4
		} else if b >= u8(0xe0) {
			i += 3
		} else if b >= u8(0xc0) {
			i += 2
		} else {
			i++
		}
		width++
	}
	return width
}

// art_line_decode turns an art file's line into bytes: the old files spell
// ANSI as the raw text \033[, which only the C compiler ever decoded; ours
// go through lip_unescape after it, where \e and \xHH live.
fn art_line_decode(line string) string {
	return lip_unescape(line.replace('\\033', '\x1b'))
}

// import_prefix answers what a generated file at out_path must climb to
// reach the project root: a file beside the run works, one under .tmp/
// climbs a level.
fn import_prefix(out_path string) string {
	dir := os.dir(out_path)
	if dir == '.' {
		return ''
	}
	return '../'.repeat(dir.count('/') + 1)
}

// bake_import spells the zig import that a generated file at out_path
// reads its bake constants from (out_bake may sit beside or below).
fn bake_import(out_path string, out_bake string) string {
	from_dir := os.dir(out_path)
	bake_dir := os.dir(out_bake)
	if from_dir == bake_dir {
		return out_bake.all_after_last('/')
	}
	prefix := import_prefix(out_path)
	// one level up either lands at the root or needs a deeper climb.
	return prefix + out_bake
}
