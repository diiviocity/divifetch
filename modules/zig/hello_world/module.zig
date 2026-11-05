// hello_world.zig — standing in for the old generator test stubs
// hello_world_c and hello_world_cpp. Those two modules differed only in the
// source language (C vs C++); the distinction dissolves in Zig, so both map
// jointly onto this single file. Like the C harness, it is compiled and
// unit-tested but never called by run.zig's printed output.
const std = @import("std");

/// The greeting, held as a compile-time string (the Zig equivalent of the
/// C stubs' module-static string buffer).
const greeting = "Hello from divifetch (zig)";

pub fn preset() []const u8 {
    return greeting;
}

test "greeting matches the C stubs' contract" {
    try std.testing.expectEqualStrings("Hello from divifetch (zig)", preset());
}
