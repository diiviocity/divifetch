// command module: runs a command and returns its whole stdout,
// with trailing newlines stripped (like the C popen loop).
//
// The shipped configs only ever hand over plain single-token commands with
// env-var-free paths (e.g. "./modules/bs/dinit"), so those are fork+exec'd
// directly via runCaptureArgv — no /bin/sh wrapper. Anything carrying shell
// syntax (operators, quotes, glob/tilde/var expansions, or more than one
// token) is routed through /bin/sh exactly as before: splitting
// quote-aware argv from strings meant for a shell needs a full shell
// parser, and a naive split would silently misbehave on things like
// `prog "arg with spaces"`. Tradeoff: the direct path is only taken where
// a plain exec is provably equivalent.
const std = @import("std");
const util = @import("../util.zig");

var out_buf: [512]u8 = undefined;

/// Characters that only a shell can give meaning to, checked per token.
const shell_meta = "$`*?{}()<>|&;'\"\\~#!";

fn hasShellSyntax(command: []const u8) bool {
    for (command) |c| {
        if (std.mem.findScalar(u8, shell_meta, c) != null) return true;
        // Whitespace means at least two tokens: let sh do the splitting.
        if (std.ascii.isWhitespace(c)) return true;
    }
    return false;
}

pub fn preset(io: std.Io, command: []const u8) []const u8 {
    if (hasShellSyntax(command)) {
        // Legacy path: sh interprets the string verbatim; stderr stays on
        // the terminal, as it did with runCapture before the fast path.
        const out = util.runCapture(io, command, &out_buf);
        return util.trimTrailingNewlines(out);
    }

    // Direct fork+exec. Deviation from the sh path: stderr is drained into
    // the buffer after stdout instead of staying on the terminal (only
    // matters if these commands print to stderr).
    const out = util.runCaptureArgv(io, &.{command}, &out_buf);
    return util.trimTrailingNewlines(out);
}
