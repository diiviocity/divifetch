// packages module — counts the installed packages of the package system
// the entry names. the entry's :args lists candidate backends, tried in
// order, and the first hit answers "N (backend)" — (packages :args
// ["pacman"]); with no :args the full list tries in the same order, so a
// bare (packages) entry reads the machine it runs on.
//
// the counters ride the former packages_* modules: apk streams the
// "\nC:Q" record signature, dpkg counts install-ok status lines, emerge
// counts two dir levels under /var/db/pkg, eopkg and pkgtool count
// non-dot entries, pacman counts the local db dirs, xbps finds the
// pkgdb-<system> file inside /var/db/xbps, and the BSD targets count
// their /var/db/pkg directories (one level: pkg_add and pkg(8) both). a backend whose db is not
// there returns none, and the next candidate gets its turn.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [32]u8 = undefined;
var chunk_buf: [16384]u8 = undefined;
var path_buf: [512]u8 = undefined;

const Backend = struct {
    name: []const u8,
    count: *const fn (io: std.Io) ?usize,
};

fn apk(io: std.Io) ?usize {
    _ = io;
    return util.countMatchesFile("/lib/apk/db/installed", "\nC:Q", &chunk_buf, 1);
}

fn dpkg(io: std.Io) ?usize {
    _ = io;
    return util.countMatchesFile("/var/lib/dpkg/status", "\nStatus: install ok installed", &chunk_buf, 0);
}

fn emerge(io: std.Io) ?usize {
    var cat_dir = std.Io.Dir.openDirAbsolute(io, "/var/db/pkg", .{ .iterate = true }) catch
        return null;
    defer cat_dir.close(io);

    var count: usize = 0;
    var cat_it = cat_dir.iterate();
    while (cat_it.next(io) catch null) |category| {
        if (category.name.len == 0 or category.name[0] == '.') continue;

        const pkg_path = std.mem.print(&path_buf, "/var/db/pkg/{s}", .{category.name}) catch continue;
        var pkg_dir = std.Io.Dir.openDirAbsolute(io, pkg_path, .{ .iterate = true }) catch continue;
        defer pkg_dir.close(io);

        var pkg_it = pkg_dir.iterate();
        while (pkg_it.next(io) catch null) |pkg| {
            if (pkg.name.len > 0 and pkg.name[0] != '.') count += 1;
        }
    }

    if (count == 0) return null;
    return count;
}

fn eopkg(io: std.Io) ?usize {
    return util.countNonDotEntries(io, "/var/lib/eopkg/package");
}

fn pacman(io: std.Io) ?usize {
    var dir = std.Io.Dir.openDirAbsolute(io, "/var/lib/pacman/local", .{ .iterate = true }) catch
        return null;
    defer dir.close(io);

    var count: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind == .directory) count += 1;
    }

    if (count == 0) return null;
    return count;
}

// the BSD package managers keep one directory per installed package
// in /var/db/pkg, a single level (openbsd's pkg_add and freebsd's
// pkg(8) share the layout, unlike emerge's category/pkg two) — one
// counter answers both names.
fn bsd_pkg_dirs(io: std.Io) ?usize {
    return util.countNonDotEntries(io, "/var/db/pkg");
}

fn pkgtool(io: std.Io) ?usize {
    return util.countNonDotEntries(io, "/var/log/packages");
}

fn xbps(io: std.Io) ?usize {
    var dir = std.Io.Dir.openDirAbsolute(io, "/var/db/xbps", .{ .iterate = true }) catch
        return null;
    defer dir.close(io);

    var found = false;
    var db_path: []const u8 = "";
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "pkgdb-")) {
            db_path = std.mem.print(&path_buf, "/var/db/xbps/{s}", .{entry.name}) catch "";
            if (db_path.len != 0) found = true;
            break;
        }
    }
    if (!found) return null;

    return util.countMatchesFile(db_path, "<string>installed</string>", &chunk_buf, 0);
}

// the distro tables split by target: an openbsd machine answers its
// own pkg_add directory, the linux backends stay linux-shaped so a
// foreign /var/db/pkg never masquerades as emerge's database.
const linux_tables = [_]Backend{
    .{ .name = "apk", .count = apk },
    .{ .name = "dpkg", .count = dpkg },
    .{ .name = "emerge", .count = emerge },
    .{ .name = "eopkg", .count = eopkg },
    .{ .name = "pacman", .count = pacman },
    .{ .name = "pkgtool", .count = pkgtool },
    .{ .name = "xbps", .count = xbps },
};
const openbsd_tables = [_]Backend{
    .{ .name = "openbsd", .count = bsd_pkg_dirs },
};
const freebsd_tables = [_]Backend{
    .{ .name = "freebsd", .count = bsd_pkg_dirs },
};
const all_tables = switch (@import("builtin").os.tag) {
    .openbsd => openbsd_tables[0..],
    .freebsd => freebsd_tables[0..],
    else => linux_tables[0..],
};

// report answers "N (backend)" or none when the backend's database is
// not on this machine.
fn report(io: std.Io, backend: Backend) ?[]const u8 {
    if (backend.count(io)) |count| {
        return std.mem.print(&value_buf, "{d} ({s})", .{ count, backend.name }) catch "?";
    }
    return null;
}

pub fn preset(io: std.Io, args: []const []const u8) []const u8 {
    // the bare form tries the full list in the same order: the machine
    // it runs on answers itself.
    if (args.len == 0) {
        for (all_tables) |backend| {
            if (report(io, backend)) |out| return out;
        }
        return "?";
    }
    for (args) |candidate| {
        for (all_tables) |backend| {
            if (!std.mem.eql(u8, candidate, backend.name)) continue;
            if (report(io, backend)) |out| return out;
        }
    }
    return "?";
}
