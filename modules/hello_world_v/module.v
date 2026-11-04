// hello_world_v module — a V sample for divifetch-zig.
//
// a V module runs once, at build time: the build script invokes this file
// with the entry's :args and its stdout bakes as the value, the way the C
// generator ran build-time entries through its header generator. shared
// libraries made of V need V's own runtime around them, so V presets print
// at bake time — no forks at fetch time, no state carried across runs.
//
// with no args it prints its text; with args it echoes them, so the
// argument pipeline is visible in the sample.
import os

fn main() {
	if os.args.len > 1 {
		println(os.args[1..].join(' '))
		return
	}
	println('Hello, World!')
}
