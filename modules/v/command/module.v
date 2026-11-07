// command module: runs the entry's command and answers its whole
// stdout, trailing newlines stripped (the C popen loop's answer).
// single-token commands without shell syntax fork+exec directly;
// anything with metacharacters or whitespace rides /bin/sh, whose
// quote-aware splitting is not worth a naive re-implementation.
//
// one gap sits V-side: os.exec merges stderr into the pipe, while the
// zig sh path left stderr on the terminal and the argv path drained it
// after stdout. outputs stay small here, so a merged capture holds.
module command

import os

// characters only a shell can give meaning to, checked per byte.
const shell_meta = '$`*?{}()<>|&;\'"\\~#!'

@[direct_array_access]
pub fn preset(cmd string) string {
	// the param rides 'cmd', not the zig lip's ':command': a V parameter
	// may not carry the module's own name
	if has_shell_syntax(cmd) {
		return capture(['/bin/sh', '-c', cmd])
	}
	// plain exec resolves a bare token off PATH, the way the zig
	// runCaptureArgv did without a shell wrapper
	return capture([cmd])
}

@[direct_array_access]
fn has_shell_syntax(cmd string) bool {
	for c in cmd.bytes() {
		if shell_meta.index_u8(c) >= 0 {
			return true
		}
		// whitespace means at least two tokens: let sh do the splitting
		if c == ` ` || c == `\t` || c == `\n` || c == `\r` || c == `\v` || c == `\f` {
			return true
		}
	}
	return false
}

// capture runs one argv and trims the output; a failed spawn keeps an
// empty answer, like the zig runCapture helpers — no '?' needed.
@[direct_array_access]
fn capture(argv []string) string {
	res := os.exec(argv)
	if res.exit_code == -1 {
		// v's exec answers the junk 'exec("…") failed' message when the
		// spawn never took off; that never counts as output
		return ''
	}
	return trim_trailing_newlines(res.output)
}

@[direct_array_access]
fn trim_trailing_newlines(out string) string {
	mut s := out
	for s.len > 0 && (s[s.len - 1] == `\n` || s[s.len - 1] == `\r`) {
		s = s[0..s.len - 1]
	}
	return s
}
