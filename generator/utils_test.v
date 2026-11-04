// utils_test.v — the pure helpers: text escapes, lip unescaping, terminal
// widths and the art decode, each against the bytes they are expected to
// produce.
module main

const sample_rune = 'ü'

fn test_zig_escape_passes_plain_bytes() {
	assert zig_escape('plain') == 'plain'
	assert zig_escape(sample_rune) == sample_rune
	assert zig_escape('') == ''
}

fn test_zig_escape_doubles_the_quote() {
	assert zig_escape('"x"') == '\\"x\\"'
}

fn test_zig_escape_doubles_the_backslash() {
	assert zig_escape('a\\b') == 'a\\\\b'
}

fn test_zig_escape_names_the_escapes() {
	assert zig_escape('a\nb') == 'a\\nb'
	assert zig_escape('a\rb') == 'a\\rb'
	assert zig_escape('a\tb') == 'a\\tb'
}

fn test_zig_escape_names_control_bytes() {
	// esc is decoded by the reader before it arrives here.
	assert zig_escape('\x1b') == '\\x1b'
	assert zig_escape('\x00') == '\\x00'
	assert zig_escape('\x7f') == '\\x7f'
	assert zig_escape('\x1f') == '\\x1f'
}

fn test_lip_unescape_passes_plain_text() {
	assert lip_unescape('no escapes') == 'no escapes'
}

fn test_lip_unescape_pairs_backslashes() {
	assert lip_unescape('a\\\\b') == 'a\\b'
}

fn test_lip_unescape_decodes_the_escape_byte() {
	assert lip_unescape('\\e[1m') == '\x1b[1m'
}

fn test_lip_unescape_decodes_hex_bytes() {
	assert lip_unescape('\\x41\\x1b\\x00') == 'A\x1b\x00'
}

fn test_lip_unescape_leaves_non_hex_families() {
	assert lip_unescape('\\xzz') == '\\xzz'
	assert lip_unescape('\\x4') == '\\x4'
}

fn test_lip_unescape_leaves_a_lone_backslash() {
	assert lip_unescape('a\\') == 'a\\'
}

fn test_lip_unescape_leaves_unknown_escapes() {
	assert lip_unescape('\\0x1B') == '\\0x1B'
	assert lip_unescape('\\q') == '\\q'
}

fn test_max_int_takes_the_larger() {
	assert max_int(-1, 3) == 3
	assert max_int(3, -1) == 3
	assert max_int(2, 2) == 2
}

fn test_visible_width_counts_plain_columns() {
	assert visible_width('hello') == 5
	assert visible_width('') == 0
}

fn test_visible_width_skips_decoded_ansi() {
	// the escape byte with a CSI tail: [...] [...] such a line is 4 columns.
	assert visible_width('\x1b[1m\x1b[0mab') == 2
	// a leading escape with no bracket prints as one column — the tail scan
	// only opens on \x1b followed by '['.
	assert visible_width('\x1b') == 1
}

fn test_visible_width_skips_the_raw_text_spelling() {
	// art files hold the escape in five raw bytes, which the old C generator
	// decoded through its printf output.
	assert visible_width('\\033[1ma') == 1
	assert visible_width('\\033[0m\\033[1mhi') == 2
}

fn test_visible_width_counts_one_column_per_rune() {
	// runes make three bytes each but are one column wide, as the old
	// generator's counting had it.
	assert visible_width('⠿⠿') == 2
	assert visible_width('ü') == 1
}

fn test_visible_width_leads_bytes_together() {
	// a two-byte rune, then a three-byte one, both one column.
	assert visible_width('é⠿') == 2
}

fn test_art_line_decode_turns_the_raw_spelling() {
	assert art_line_decode('\\033[1mcat') == '\x1b[1mcat'
}

fn test_art_line_decode_rides_lip_unescape() {
	// \e and \xHH live through blip's reader untouched, so the decoder
	// carries both, and a quoted pair still yields one backslash.
	assert art_line_decode('\\e[0m') == '\x1b[0m'
	assert art_line_decode('\\x41') == 'A'
	assert art_line_decode('\\\\') == '\\'
}

fn test_v_escape_doubles_backslashes_and_quotes() {
	assert v_escape("a'b") == "a\\'b"
	assert v_escape('a\\b') == 'a\\\\b'
	assert v_escape('plain') == 'plain'
}
