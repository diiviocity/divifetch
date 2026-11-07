// hello_world module — standing in for the old generator test stubs
// hello_world_c and hello_world_cpp. those two differed only in the
// source language; the distinction dissolves over here, leaving one
// compiled stub that never rides the fetch's printed output.
module hello_world

// the greeting, held as a compile-time string (the V equivalent of the
// C stubs' module-static string buffer)
const greeting = 'Hello from divifetch (v)'

@[direct_array_access]
pub fn preset() string {
	return greeting
}
