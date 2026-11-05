// font module — the running terminal's configured font, per-terminal
// parsing stolen from fastfetch's detection/terminalfont (see
// ~/git/fastfetch). Zero spawn. Identity comes from the shared terminal
// module detector (env hints + PID /proc/<pid>/comm, TERM_PROGRAM,
// process walk, $TERM). Per terminal:
//   kitty        .config/kitty/kitty.conf: font_family (default monospace)
//   alacritty    alacritty.toml/yml: quoted family =
//   foot         foot.ini: font=, Xft pattern, comma fallback list
//                (first entry), trailing "-<size>/str" suffixes stripped
//   ghostty      ghostty/config: font-family=
//   konsole      konsolerc DefaultProfile -> profile Font= (truncated at
//                the first comma); built-in profile default -> monospace
//   deepin       deepin config.conf via [basic.interface.font] section,
//                value= lines; default "Noto Sans Mono"
//   qterminal    qterminal.ini: fontFamily= / fontSize= (joined)
//   lxterminal   lxterminal.conf: fontname =
//   sakura, termite, weston, kmscon, cosmic-term, xfce4-terminal: the
//                plain-file/line parsers as in fastfetch
//   terminator   config with use_system_font handling (system font alias)
//   xterm        .Xresources/.Xdefaults faceName; default "fixed"
//   st           -f cmdline override via /proc/<pid>/cmdline, else
//                binary string scrape of the st executable (fastfetch
//                ffBinaryExtractStrings, first string containing "size=")
//   urxvt        URxvt.font: Xft or XLFD field parsing
//   wezterm      .wezterm.lua first string in wezterm.font(...)
// Consciously NOT stolen (would drag dependencies): the GNOME gconf ring
// (gnome-terminal/tilix/mate/kgx/ptyxis — fastfetch dlopens libgio) and
// warp (yyjson). Those stay "?".
const std = @import("std");
const util = @import("../util.zig");
const terminal = @import("../terminal/module.zig");

var value_buf: [128]u8 = undefined;
var base_buf: [128]u8 = undefined;
var share_buf: [128]u8 = undefined;
var path_buf: [128]u8 = undefined;
var home_buf: [128]u8 = undefined;
var file_buf: [8192]u8 = undefined;
var profile_buf: [2048]u8 = undefined;
var scrape_buf: [16384]u8 = undefined;
var str_buf: [256]u8 = undefined;

/// Config root: XDG_CONFIG_HOME when non-empty, else $HOME/.config.
pub fn configBase(environ: *const std.process.Environ.Map) ?[]const u8 {
    if (environ.get("XDG_CONFIG_HOME")) |x| {
        if (x.len != 0) return util.snapshot(&base_buf, x);
    }
    const home = environ.get("HOME") orelse return null;
    return std.mem.print(&base_buf, "{s}/.config", .{home}) catch null;
}

fn firstQuoted(haystack: []const u8) []const u8 {
    const start = std.mem.findScalar(u8, haystack, '"') orelse return "";
    const rest = haystack[start + 1 ..];
    const end = std.mem.findScalar(u8, rest, '"') orelse return "";
    return rest[0..end];
}

/// Value reader for `key<sep>value` ini-ish lines, allowing spaces around
/// the separator. Returns the trimmed value at first hit.
fn iniValue(content: []const u8, key: []const u8, sep: u8) []const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trimStart(u8, line_raw, " \t");
        if (!std.mem.startsWith(u8, line, key)) continue;
        const after = line[key.len..];
        if (after.len == 0) continue;
        if (after[0] != sep) {
            const t = std.mem.trimStart(u8, after, " \t");
            if (t.len == 0 or t[0] != sep) continue;
            return std.mem.trim(u8, t[1..], " \t\r");
        }
        return std.mem.trim(u8, after[1..], " \t\r");
    }
    return "";
}

/// Xft "Family[size][:options]" -> family, with the trailing "-<size>"
/// and everything after ":" removed (foot's font=, st's patterns).
fn xftFamily(pattern: []const u8) []const u8 {
    var text = pattern;
    if (std.mem.findScalar(u8, text, ':')) |colon| text = text[0..colon];
    text = std.mem.trim(u8, text, " \t");

    // trailing -<digits>[.<digits>] is a size, not part of the family
    if (std.mem.findScalarLast(u8, text, '-')) |dash| {
        const tail = text[dash + 1 ..];
        if (tail.len > 0 and std.ascii.isDigit(tail[0])) {
            var i: usize = 0;
            while (i < tail.len and (std.ascii.isDigit(tail[i]) or tail[i] == '.')) i += 1;
            if (i == tail.len) text = std.mem.trimEnd(u8, text[0..dash], " \t");
        }
    }
    return text;
}

/// XLFD "-vendor-family-weight-slant-setwidth-addstyle-pixelsize..."
/// -> the family (field 2 after the leading dash).
fn xlfdFamily(pattern: []const u8) []const u8 {
    if (pattern.len == 0 or pattern[0] != '-') return "";
    var field: usize = 0;
    var start: usize = 1;
    if (std.mem.findScalar(u8, pattern[1..], '-') == null) return "";
    var it = std.mem.splitScalar(u8, pattern[1..], '-');
    _ = &start;
    while (it.next()) |f| {
        if (field == 1) return std.mem.trim(u8, f, " *");
        field += 1;
    }
    return "";
}

// ---------------------------------------------------------------------
// per-terminal parsers

fn parseKitty(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/kitty/kitty.conf", .{base}) catch return null;
    if (util.readWholeFile(path, &file_buf)) |conf| {
        var lines = std.mem.splitScalar(u8, conf, '\n');
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "font_family")) continue;
            const val = std.mem.trim(u8, line["font_family".len..], " \t");
            if (val.len == 0 or val[0] == '#') continue;
            return util.snapshot(&value_buf, val);
        }
    }
    // kitty with no font_family uses fontconfig's monospace alias —
    // fastfetch models this as the real default.
    return util.snapshot(&value_buf, "monospace");
}

fn parseAlacritty(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const files = [_][]const u8{ "alacritty/alacritty.toml", "alacritty/alacritty.yml" };
    for (files) |file| {
        const path = std.mem.print(&path_buf, "{s}/{s}", .{ base, file }) catch continue;
        const conf = util.readWholeFile(path, &file_buf) orelse continue;
        var lines = std.mem.splitScalar(u8, conf, '\n');
        while (lines.next()) |line| {
            const eq = std.mem.findScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            if (!std.mem.eql(u8, key, "family")) continue;
            const family = std.mem.trim(u8, firstQuoted(line[eq + 1 ..]), " \t");
            if (family.len != 0) return util.snapshot(&value_buf, family);
        }
    }
    return null;
}

fn parseFoot(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/foot/foot.ini", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse {
        // foot's built-in default
        return util.snapshot(&value_buf, "monospace");
    };
    var lines = std.mem.splitScalar(u8, conf, '\n');
    while (lines.next()) |line| {
        const eq = std.mem.findScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (!std.mem.eql(u8, key, "font")) continue;
        var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len == 0) break;
        // foot splits fallback fonts on commas: first entry only
        if (std.mem.findScalar(u8, val, ',')) |comma| val = val[0..comma];
        const family = xftFamily(val);
        if (family.len != 0) return util.snapshot(&value_buf, family);
        break;
    }
    return util.snapshot(&value_buf, "monospace");
}

fn parseGhostty(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/ghostty/config", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;
    var lines = std.mem.splitScalar(u8, conf, '\n');
    while (lines.next()) |line| {
        const eq = std.mem.findScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (!std.mem.eql(u8, key, "font-family")) continue;
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len != 0) return util.snapshot(&value_buf, val);
    }
    return null;
}

fn parseKonsole(io: std.Io, environ: *const std.process.Environ.Map) ?[]const u8 {
    const base = configBase(environ) orelse return null;

    const share_root: []const u8 = blk: {
        if (environ.get("XDG_DATA_HOME")) |x| {
            if (x.len != 0) break :blk util.snapshot(&share_buf, x);
        }
        const home = environ.get("HOME") orelse return null;
        break :blk std.mem.print(&share_buf, "{s}/.local/share", .{home}) catch return null;
    };

    // Preferred: konsolerc's DefaultProfile.
    {
        const kpath = std.mem.print(&path_buf, "{s}/konsole/konsolerc", .{base}) catch return null;
        if (util.readWholeFile(kpath, &file_buf)) |conf| {
            var lines = std.mem.splitScalar(u8, conf, '\n');
            while (lines.next()) |line| {
                if (!std.mem.startsWith(u8, line, "DefaultProfile=")) continue;
                const profile = std.mem.trimEnd(u8, line["DefaultProfile=".len..], " \t\r");
                if (profile.len == 0) {
                    // "Built-in profile is used": konsole's default font
                    return util.snapshot(&value_buf, "monospace");
                }
                const fpath = std.mem.print(&path_buf, "{s}/konsole/{s}", .{ share_root, profile }) catch return null;
                const pf = util.readWholeFile(fpath, &profile_buf) orelse return null;
                var plines = std.mem.splitScalar(u8, pf, '\n');
                while (plines.next()) |pline| {
                    if (!std.mem.startsWith(u8, pline, "Font=")) continue;
                    const val = std.mem.trimEnd(u8, pline["Font=".len..], " \t\r");
                    const comma = std.mem.findScalar(u8, val, ',') orelse val.len;
                    if (comma == 0) break;
                    return util.snapshot(&value_buf, val[0..comma]);
                }
                return null;
            }
        }
    }

    // Fallback: first profile file in the data dir.
    const dpath = std.mem.print(&path_buf, "{s}/konsole", .{share_root}) catch return null;
    var dir = std.Io.Dir.openDirAbsolute(io, dpath, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".profile")) continue;
        const fpath = std.mem.print(&path_buf, "{s}/konsole/{s}", .{ share_root, entry.name }) catch continue;
        const pf = util.readWholeFile(fpath, &profile_buf) orelse continue;
        var plines = std.mem.splitScalar(u8, pf, '\n');
        while (plines.next()) |pline| {
            if (!std.mem.startsWith(u8, pline, "Font=")) continue;
            const val = std.mem.trimEnd(u8, pline["Font=".len..], " \t\r");
            const comma = std.mem.findScalar(u8, val, ',') orelse val.len;
            if (comma == 0) break;
            return util.snapshot(&value_buf, val[0..comma]);
        }
    }
    return util.snapshot(&value_buf, "monospace"); // built-in default profile
}

fn parseDeepin(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/deepin/deepin-terminal/config.conf", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;

    var family: []const u8 = "";
    var size: []const u8 = "";
    var lines = std.mem.splitScalar(u8, conf, '\n');
    while (lines.next()) |line| {
        const terminated = std.mem.trimEnd(u8, line, " \t\r");
        if (family.len == 0 and std.mem.eql(u8, terminated, "[basic.interface.font]")) {
            family = iniValue(lines.next() orelse "", "value", '=');
        } else if (size.len == 0 and std.mem.eql(u8, terminated, "[basic.interface.font_size]")) {
            size = iniValue(lines.next() orelse "", "value", '=');
        }
        if (family.len != 0 and size.len != 0) break;
    }
    if (family.len == 0) return util.snapshot(&value_buf, "Noto Sans Mono"); // fastfetch default
    return util.snapshot(&value_buf, family);
}

fn parseQTerminal(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/qterminal.org/qterminal.ini", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return util.snapshot(&value_buf, "monospace"); // fastfetch default

    var family = iniValue(conf, "fontFamily=", '=');
    const size = iniValue(conf, "fontSize=", '=');
    if (family.len == 0) return util.snapshot(&value_buf, "monospace");
    family = util.snapshot(&value_buf, family);
    if (size.len != 0) return std.mem.print(&value_buf, "{s} {s}", .{ family, size }) catch family;
    return family;
}

fn parseSimple(environ: *const std.process.Environ.Map, base: []const u8, subpath: []const u8, key: []const u8) ?[]const u8 {
    _ = environ;
    // sakura/sakura.conf "font=", termite/config "font =",
    // lxterminal/lxterminal.conf "fontname ="
    const path = std.mem.print(&path_buf, "{s}/{s}", .{ base, subpath }) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;
    const val = iniValue(conf, key, ' ');
    if (val.len == 0) return null;
    return util.snapshot(&value_buf, val);
}

fn parseWeston(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/weston.ini", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;
    var family = iniValue(conf, "font=", '=');
    const size = iniValue(conf, "font-size=", '=');
    if (family.len == 0) family = "DejaVu Sans Mono"; // fastfetch default
    family = util.snapshot(&value_buf, family);
    if (size.len != 0) return std.mem.print(&value_buf, "{s} {s}", .{ family, size }) catch family;
    return family;
}

fn parseKmscon(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/kmscon/kmscon.conf", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;
    var family = iniValue(conf, "font-name=", '=');
    const size = iniValue(conf, "font-size=", '=');
    if (family.len == 0) family = "Hack Nerd Font"; // fastfetch default
    family = util.snapshot(&value_buf, family);
    if (size.len != 0) return std.mem.print(&value_buf, "{s} {s}", .{ family, size }) catch family;
    return family;
}

fn parseCosmic(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    // $CONFIG/cosmic/com.system76.CosmicTerm/v1/font_name (+font_size)
    const path = std.mem.print(&path_buf, "{s}/cosmic/com.system76.CosmicTerm/v1/font_name", .{base}) catch return null;
    var family: []const u8 = "";
    if (util.readWholeFile(path, &file_buf)) |raw| {
        family = std.mem.trim(u8, std.mem.trim(u8, raw, " \t\r"), "\"");
    }
    if (family.len == 0) return util.snapshot(&value_buf, "Noto Sans Mono"); // fastfetch default
    return util.snapshot(&value_buf, family);
}

fn parseXfce(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ; // xfconf reads are file-only here
    // xfce4-terminal.xml (xfconf): attribute-substring extraction per line;
    // then the older terminalrc. System font answers via the monospace
    // alias (xfconf's XfSettings would need xfconf — not stolen).
    {
        const path = std.mem.print(&path_buf, "{s}/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml", .{base}) catch return null;
        if (util.readWholeFile(path, &file_buf)) |xml| {
            var useSystem = false;
            var lines = std.mem.splitScalar(u8, xml, '\n');
            while (lines.next()) |line| {
                if (std.mem.find(u8, line, "<property name=\"font-use-system\"") == null) continue;
                useSystem = std.mem.find(u8, line, "value=\"true\"") != null;
            }

            lines = std.mem.splitScalar(u8, xml, '\n');
            while (lines.next()) |line| {
                const prop = std.mem.find(u8, line, "<property name=\"font-name\"") orelse continue;
                const from = line[prop..];
                const vstart = std.mem.find(u8, from, "value=\"") orelse continue;
                const rest = from[vstart + "value=\"".len ..];
                const end = std.mem.findScalar(u8, rest, '"') orelse continue;
                if (end == 0) continue;
                if (useSystem) return util.snapshot(&value_buf, "monospace");
                return util.snapshot(&value_buf, rest[0..end]);
            }
        }
    }
    // legacy terminalrc
    const legacy = std.mem.print(&path_buf, "{s}/xfce4/terminal/terminalrc", .{base}) catch return null;
    const rc = util.readWholeFile(legacy, &file_buf) orelse return null;
    const family = iniValue(rc, "FontName ", ' ');
    if (family.len != 0) return util.snapshot(&value_buf, family);
    return null;
}

fn parseTerminator(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    _ = environ;
    const path = std.mem.print(&path_buf, "{s}/terminator/config", .{base}) catch return null;
    const conf = util.readWholeFile(path, &file_buf) orelse return null;
    const useSystem = iniValue(conf, "use_system_font", '=');
    const family = iniValue(conf, "font", '=');
    // fastfetch: use_system_font=True means the GSettings monospace;
    // we can't read dconf without glib, so alias the system font.
    if (std.ascii.eqlIgnoreCase(useSystem, "true")) return util.snapshot(&value_buf, "monospace");
    if (family.len != 0) return util.snapshot(&value_buf, family);
    return util.snapshot(&value_buf, "Mono"); // fastfetch default
}

fn parseXterm(environ: *const std.process.Environ.Map) ?[]const u8 {
    const home = environ.get("HOME") orelse return null;
    const files = [_][]const u8{ ".Xresources", ".Xdefaults" };
    for (files) |file| {
        const xpath = std.mem.print(&path_buf, "{s}/{s}", .{ home, file }) catch continue;
        const conf = util.readWholeFile(xpath, &file_buf) orelse continue;
        var lines = std.mem.splitScalar(u8, conf, '\n');
        while (lines.next()) |line| {
            if (std.mem.find(u8, line, "xterm*faceName") == null and
                std.mem.find(u8, line, "xterm.vt100.faceName") == null) continue;
            const colon = std.mem.findScalar(u8, line, ':') orelse continue;
            const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (val.len != 0) return util.snapshot(&value_buf, val);
        }
    }
    return util.snapshot(&value_buf, "fixed"); // xterm's own default
}

fn parseUrxvt(environ: *const std.process.Environ.Map) ?[]const u8 {
    const home = environ.get("HOME") orelse return null;
    const files = [_][]const u8{ ".Xresources", ".Xdefaults" };
    for (files) |file| {
        const xpath = std.mem.print(&path_buf, "{s}/{s}", .{ home, file }) catch continue;
        const conf = util.readWholeFile(xpath, &file_buf) orelse continue;
        var lines = std.mem.splitScalar(u8, conf, '\n');
        while (lines.next()) |line| {
            if (std.mem.find(u8, line, "URxvt.font") == null) continue;
            const colon = std.mem.findScalar(u8, line, ':') orelse continue;
            var val = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (val.len == 0) continue;
            // entries: commas are fallback chains — first only
            if (std.mem.findScalar(u8, val, ',')) |comma| val = val[0..comma];
            val = std.mem.trim(u8, val, " \t");
            if (val.len != 0 and val[0] == '-') {
                const family = xlfdFamily(val);
                if (family.len != 0) return util.snapshot(&value_buf, family);
                continue;
            }
            if (std.mem.startsWith(u8, val, "xft:")) val = val[4..];
            const family = xftFamily(val);
            if (family.len != 0) return util.snapshot(&value_buf, family);
        }
    }
    return null; // fastfetch errors out here; we stay "?" honest
}

fn parseWezterm(environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    // .wezterm.lua lives in $HOME (or XDG_CONFIG_HOME for some setups)
    var paths: [2][]const u8 = undefined;
    var n: usize = 0;
    if (environ.get("HOME")) |home| {
        paths[n] = std.mem.print(&path_buf, "{s}/.wezterm.lua", .{home}) catch "";
        if (paths[n].len != 0) n += 1;
    }
    const xdg = std.mem.print(&home_buf, "{s}/wezterm/wezterm.lua", .{base}) catch "";
    if (xdg.len != 0 and n < 2) {
        paths[n] = xdg;
        n += 1;
    }
    for (paths[0..n]) |lpath| {
        const conf = util.readWholeFile(lpath, &file_buf) orelse continue;
        const at = std.mem.find(u8, conf, "wezterm.font(") orelse continue;
        const family = firstQuoted(conf[at + "wezterm.font(".len ..]);
        if (family.len != 0) return util.snapshot(&value_buf, family);
    }
    return null;
}

/// st hardcodes its font in config.h: it either runs with `-f <xft>` (an
/// argv override readable from /proc/<pid>/cmdline) or the pattern lives
/// inside the binary — fastfetch scrapes the first NUL-string containing
/// "size=" from the executable itself.
fn stFont(io: std.Io, info: terminal.Info, environ: *const std.process.Environ.Map) ?[]const u8 {
    _ = io;
    _ = environ;
    if (info.pid <= 0) return null;

    // 1) argv override: whole /proc/<pid>/cmdline, "\0-f\0" sequence.
    {
        var cmd_buf: [512]u8 = undefined;
        const cpath = std.mem.print(&cmd_buf, "/proc/{d}/cmdline", .{info.pid}) catch return null;
        if (util.readWholeFile(cpath, &file_buf)) |argv| {
            var i: usize = 0;
            while (i + 3 < argv.len) : (i += 1) {
                if (argv[i] == 0 and argv[i + 1] == '-' and argv[i + 2] == 'f' and argv[i + 3] == 0) {
                    var j = i + 4;
                    while (j < argv.len and argv[j] != 0) : (j += 1) {}
                    const family = xftFamily(argv[i + 4 .. j]);
                    if (family.len != 0) return util.snapshot(&value_buf, family);
                }
            }
        }
    }

    // 2) scrape the binary.
    var rp_buf: [64:0]u8 = undefined;
    const epath = std.mem.print(&rp_buf, "/proc/{d}/exe", .{info.pid}) catch return null;
    var exe_buf: [128]u8 = undefined;
    // readlink is a raw syscall passthrough in 0.17: on failure the
    // result is a negated errno, so a negative isize means "failed".
    var exe_buf_z: [128:0]u8 = undefined;
    @memcpy(exe_buf_z[0..epath.len], epath);
    exe_buf_z[epath.len] = 0;
    const exe_len = std.os.linux.readlink(&exe_buf_z, &exe_buf, exe_buf.len);
    if (@as(isize, @bitCast(exe_len)) < 0) return null;
    const exe = exe_buf[0..@intCast(exe_len)];

    const fd = std.posix.openat(std.posix.AT.FDCWD, exe, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer _ = std.os.linux.close(fd);

    // Chunked NUL-string scan to EOF: scrape_buf is a fixed window, the
    // file itself can be far bigger (st's config strings live in
    // .rodata, past the ELF headers).
    var len: usize = 0;
    while (true) {
        const n = std.posix.read(fd, &scrape_buf) catch break;
        if (n == 0) break;
        for (scrape_buf[0..n]) |c| {
            if (c == 0 or c < 32) {
                if (len != 0) {
                    if (std.mem.find(u8, str_buf[0..len], "size=") != null) {
                        const family = xftFamily(str_buf[0..len]);
                        if (family.len != 0) return util.snapshot(&value_buf, family);
                    }
                    len = 0;
                }
            } else if (len < str_buf.len) {
                str_buf[len] = c;
                len += 1;
            }
        }
    }
    if (len != 0) {
        if (std.mem.find(u8, str_buf[0..len], "size=") != null) {
            const family = xftFamily(str_buf[0..len]);
            if (family.len != 0) return util.snapshot(&value_buf, family);
        }
    }
    return null;
}

/// Family for the detected terminal; null = unknown/unset (?", like the
/// fastfetch dispatch reaching its else branch).
pub fn fontOf(io: std.Io, info: terminal.Info, environ: *const std.process.Environ.Map, base: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, info.name, "kitty")) return parseKitty(environ, base);
    if (std.mem.eql(u8, info.name, "alacritty")) return parseAlacritty(environ, base);
    if (std.mem.eql(u8, info.name, "foot")) return parseFoot(environ, base);
    if (std.mem.eql(u8, info.name, "ghostty")) return parseGhostty(environ, base);
    if (std.mem.eql(u8, info.name, "konsole") or std.mem.eql(u8, info.name, "yakuake")) return parseKonsole(io, environ);
    if (std.mem.eql(u8, info.name, "deepin-terminal")) return parseDeepin(environ, base);
    if (std.mem.eql(u8, info.name, "qterminal")) return parseQTerminal(environ, base);
    if (std.mem.eql(u8, info.name, "lxterminal")) return parseSimple(environ, base, "lxterminal/lxterminal.conf", "fontname ");
    if (std.mem.eql(u8, info.name, "sakura")) return parseSimple(environ, base, "sakura/sakura.conf", "font ");
    if (std.mem.eql(u8, info.name, "termite")) return parseSimple(environ, base, "termite/config", "font ");
    if (std.mem.eql(u8, info.name, "weston-terminal")) return parseWeston(environ, base);
    if (std.mem.eql(u8, info.name, "kmscon")) return parseKmscon(environ, base);
    if (std.mem.eql(u8, info.name, "cosmic-term")) return parseCosmic(environ, base);
    if (std.mem.eql(u8, info.name, "xfce4-terminal")) return parseXfce(environ, base);
    if (std.mem.eql(u8, info.name, "terminator")) return parseTerminator(environ, base);
    if (std.mem.eql(u8, info.name, "xterm")) return parseXterm(environ);
    if (std.mem.eql(u8, info.name, "urxvt") or std.mem.eql(u8, info.name, "rxvt")) return parseUrxvt(environ);
    if (std.mem.eql(u8, info.name, "wezterm")) return parseWezterm(environ, base);
    if (std.mem.eql(u8, info.name, "st")) return stFont(io, info, environ);
    return null;
}

pub fn preset(io: std.Io, environ: *const std.process.Environ.Map) []const u8 {
    const info = terminal.detect(io, environ);
    if (info.name.len == 0) return "?";

    const base = configBase(environ) orelse return "?";
    return fontOf(io, info, environ, base) orelse "?";
}
