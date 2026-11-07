// cpu module: model name, core/thread count and current frequency,
// all from /proc/cpuinfo + cpufreq sysfs. Zero spawn, static buffer.
// openbsd answers the same three facts from hw.model, hw.ncpuonline
// and hw.cpuspeed; freebsd from hw.model, hw.ncpu, dev.cpu.0.freq.
const std = @import("std");
const util = @import("../util.zig");

var value_buf: [160]u8 = undefined;
var model_buf: [128]u8 = undefined;
var file_buf: [8192]u8 = undefined;
var freq_buf: [32]u8 = undefined;
var obs_model_buf: [128]u8 = undefined;
var obs_freq_buf: [32]u8 = undefined;

pub fn preset() []const u8 {
    if (@import("builtin").os.tag == .openbsd) return openbsdPreset();
    if (@import("builtin").os.tag == .freebsd) return freebsdPreset();
    if (@import("builtin").os.tag == .macos) return macosPreset();

    var model: []const u8 = "";
    var cores: usize = 0;

    // "model name\t: Intel Core i5-12400" (x86) or "Hardware: ..." (arm)
    const content = util.readWholeFile("/proc/cpuinfo", &file_buf) orelse return "?";
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.findScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (val.len == 0) continue;
        if (std.mem.eql(u8, key, "processor")) {
            cores += 1;
        } else if (model.len == 0 and
            (std.mem.eql(u8, key, "model name") or std.mem.eql(u8, key, "Hardware")))
        {
            model = util.snapshot(&model_buf, val);
        }
    }
    if (model.len == 0) return "?";

    // "Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz" — cut the model's own
    // static speed so the live cpufreq figure below isn't doubled up.
    if (std.mem.find(u8, model, " @ ")) |at| {
        model = std.mem.trimEnd(u8, model[0..at], " \t");
    }

    // Current frequency of the first core, if cpufreq exposes one.
    if (util.readFirstLine("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", &freq_buf)) |raw| {
        if (std.fmt.parseInt(u64, raw, 10)) |khz| {
            const ghz: f64 = @as(f64, @floatFromInt(khz)) / 1_000_000.0;
            if (cores != 0)
                return std.mem.print(&value_buf, "{s} ({d}) @ {d:.2}GHz", .{ model, cores, ghz }) catch "?";
            return std.mem.print(&value_buf, "{s} @ {d:.2}GHz", .{ model, ghz }) catch "?";
        } else |_| {}
    }

    if (cores != 0) return std.mem.print(&value_buf, "{s} ({d})", .{ model, cores }) catch "?";
    return util.snapshot(&value_buf, model);
}

fn openbsdPreset() []const u8 {
    const obs = @import("../openbsd.zig");
    const raw = obs.hwStr(obs.HW_MODEL, &obs_model_buf) orelse return "?";
    var model = util.snapshot(&model_buf, raw);

    // "Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz" — cut the model's own
    // static speed, the way the linux side does, so the live hw.cpuspeed
    // below isn't doubled up.
    if (std.mem.find(u8, model, " @ ")) |at| {
        model = std.mem.trimEnd(u8, model[0..at], " \t");
    }
    model = std.mem.trimEnd(u8, model, " \t");
    if (model.len == 0) return "?";

    const cores = obs.hwInt(obs.HW_NCPUONLINE) orelse 0; // hw.ncpuonline
    const mhz_i = obs.hwInt(obs.HW_CPUSPEED); // hw.cpuspeed
    if (mhz_i) |mhz| {
        const ghz: f64 = @as(f64, @floatFromInt(mhz)) / 1000.0;
        if (cores != 0)
            return std.mem.print(&value_buf, "{s} ({d}) @ {d:.2}GHz", .{ model, cores, ghz }) catch "?";
        return std.mem.print(&value_buf, "{s} @ {d:.2}GHz", .{ model, ghz }) catch "?";
    }
    if (cores != 0)
        return std.mem.print(&value_buf, "{s} ({d})", .{ model, cores }) catch "?";
    return util.snapshot(&value_buf, model);
}

fn freebsdPreset() []const u8 {
    const f = @import("../freebsd.zig");
    var model_raw: [128]u8 = undefined;
    const raw = f.cpuModel(&model_raw) orelse return "?";
    var model = util.snapshot(&model_buf, raw);

    // "Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz" — cut the model's own
    // static speed like the linux and openbsd sides, so the live
    // dev.cpu.0.freq below isn't doubled up.
    if (std.mem.find(u8, model, " @ ")) |at| {
        model = std.mem.trimEnd(u8, model[0..at], " \t");
    }
    model = std.mem.trimEnd(u8, model, " \t");
    if (model.len == 0) return "?";

    const cores = f.ncpu() orelse 0;
    const mhz_i = f.cpuFreqMhz();
    if (mhz_i) |mhz| {
        const ghz: f64 = @as(f64, @floatFromInt(mhz)) / 1000.0;
        if (cores != 0)
            return std.mem.print(&value_buf, "{s} ({d}) @ {d:.2}GHz", .{ model, cores, ghz }) catch "?";
        return std.mem.print(&value_buf, "{s} @ {d:.2}GHz", .{ model, ghz }) catch "?";
    }
    if (cores != 0)
        return std.mem.print(&value_buf, "{s} ({d})", .{ model, cores }) catch "?";
    return util.snapshot(&value_buf, model);
}

// macOS: machdep.cpu.brand_string + hw.ncpu + hw.cpufrequency. Apple
// silicon publishes no frequency at all ("Apple M2 Pro (12)"); Intel
// Macs answer their nominal clock in Hz.
fn macosPreset() []const u8 {
    const m = @import("../macos.zig");
    var model_raw: [128]u8 = undefined;
    const raw = m.cpuModel(&model_raw) orelse return "?";
    var model = util.snapshot(&model_buf, raw);

    if (std.mem.find(u8, model, " @ ")) |at| {
        model = std.mem.trimEnd(u8, model[0..at], " \t");
    }
    model = std.mem.trimEnd(u8, model, " \t");
    if (model.len == 0) return "?";

    const cores = m.ncpu() orelse 0;
    if (m.cpuFreqHz()) |hz| {
        if (hz > 0) {
            const ghz: f64 = @as(f64, @floatFromInt(hz)) / 1_000_000_000.0;
            if (cores != 0)
                return std.mem.print(&value_buf, "{s} ({d}) @ {d:.2}GHz", .{ model, cores, ghz }) catch "?";
            return std.mem.print(&value_buf, "{s} @ {d:.2}GHz", .{ model, ghz }) catch "?";
        }
    }
    if (cores != 0)
        return std.mem.print(&value_buf, "{s} ({d})", .{ model, cores }) catch "?";
    return util.snapshot(&value_buf, model);
}
