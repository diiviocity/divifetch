// darwin: the macOS framework plumbing the V modules share — the V side
// of modules/zig/macos.zig's IOKit block. CoreFoundation and IOKit are
// not libSystem, and neither the native linker nor a freestanding build
// links frameworks, but every macOS carries both in the dyld shared
// cache: dlopen/dlsym are libSystem's, so each call resolves its symbol
// and runs through a typed function pointer. Detection logic follows
// fastfetch (~/git/fastfetch/src/common/apple, detection/*_apple.*).
//
// A missing framework or symbol degrades to none / zero / nil, never a
// crash: every module that uses this answers '?' then.
module darwin

fn C.dlopen(path &char, mode i32) voidptr
fn C.dlsym(handle voidptr, name &char) voidptr
fn C.sysctlbyname(name &char, oldp voidptr, oldlenp &uint, newp voidptr, newlen uint) i32

const rtld_lazy = i32(1)
const rtld_default = voidptr(u64(0xfffffffffffffffe)) // (void *)-2
const cf_utf8 = u32(0x08000100) // kCFStringEncodingUTF8
const cf_number_sint64 = i64(4) // kCFNumberSInt64Type
const cf_number_float64 = i64(6) // kCFNumberFloat64Type

fn cf_lib() voidptr {
	return C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
		rtld_lazy)
}

fn iokit_lib() voidptr {
	return C.dlopen(c'/System/Library/Frameworks/IOKit.framework/IOKit', rtld_lazy)
}

// sym resolves `name` in `lib`; nil when the library or the symbol is
// missing, which every wrapper checks before it casts.
fn sym(lib voidptr, name &char) voidptr {
	if lib == unsafe { nil } {
		return unsafe { nil }
	}
	return C.dlsym(lib, name)
}

// ─── CoreFoundation ────────────────────────────────────────────────────

type FnRelease = fn (voidptr)

type FnStrCreate = fn (voidptr, &char, u32) voidptr

type FnGet2 = fn (voidptr, voidptr) voidptr

type FnNumGet = fn (voidptr, i64, voidptr) u8

type FnBool1 = fn (voidptr) u8

type FnBool2 = fn (voidptr, voidptr) u8

type FnCount = fn (voidptr) i64

type FnAt = fn (voidptr, i64) voidptr

type FnStrGet = fn (voidptr, &u8, i64, u32) u8

type FnTypeOf = fn (voidptr) u64

type FnTypeId = fn () u64

type FnBytes = fn (voidptr) &u8

type FnPlist = fn (voidptr, voidptr, u64, voidptr, voidptr) voidptr

type FnUid = fn (voidptr) u32

type FnDictAdd = fn (voidptr, voidptr, voidptr)

// release drops one CF reference; nil passes.
pub fn release(obj voidptr) {
	if obj == unsafe { nil } {
		return
	}
	p := sym(cf_lib(), c'CFRelease')
	if p == unsafe { nil } {
		return
	}
	f := unsafe { FnRelease(p) }
	f(obj)
}

// cfstr makes a CFString the caller releases; nil on failure.
pub fn cfstr(s string) voidptr {
	p := sym(cf_lib(), c'CFStringCreateWithCString')
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	f := unsafe { FnStrCreate(p) }
	return f(unsafe { nil }, &char(s.str), cf_utf8)
}

fn type_id(name &char) u64 {
	p := sym(cf_lib(), name)
	if p == unsafe { nil } {
		return 0
	}
	f := unsafe { FnTypeId(p) }
	return f()
}

fn type_of(obj voidptr) u64 {
	if obj == unsafe { nil } {
		return 0
	}
	p := sym(cf_lib(), c'CFGetTypeID')
	if p == unsafe { nil } {
		return 0
	}
	f := unsafe { FnTypeOf(p) }
	return f(obj)
}

pub fn is_string(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'CFStringGetTypeID')
}

pub fn is_data(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'CFDataGetTypeID')
}

pub fn is_dict(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'CFDictionaryGetTypeID')
}

pub fn is_array(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'CFArrayGetTypeID')
}

pub fn is_number(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'CFNumberGetTypeID')
}

pub fn is_uid(obj voidptr) bool {
	t := type_of(obj)
	return t != 0 && t == type_id(c'_CFKeyedArchiverUIDGetTypeID')
}

// dict_get looks `key` up in a CFDictionary; the value is borrowed (no
// release). nil when absent.
pub fn dict_get(dict voidptr, key string) voidptr {
	if dict == unsafe { nil } {
		return unsafe { nil }
	}
	p := sym(cf_lib(), c'CFDictionaryGetValue')
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	k := cfstr(key)
	if k == unsafe { nil } {
		return unsafe { nil }
	}
	defer {
		release(k)
	}
	f := unsafe { FnGet2(p) }
	return f(dict, k)
}

// dict_add stores `value` under the string `key` in a mutable dictionary.
pub fn dict_add(dict voidptr, key string, value voidptr) {
	p := sym(cf_lib(), c'CFDictionaryAddValue')
	if p == unsafe { nil } || dict == unsafe { nil } || value == unsafe { nil } {
		return
	}
	k := cfstr(key)
	if k == unsafe { nil } {
		return
	}
	defer {
		release(k)
	}
	f := unsafe { FnDictAdd(p) }
	f(dict, k, value)
}

pub fn array_count(arr voidptr) i64 {
	if arr == unsafe { nil } {
		return 0
	}
	p := sym(cf_lib(), c'CFArrayGetCount')
	if p == unsafe { nil } {
		return 0
	}
	f := unsafe { FnCount(p) }
	return f(arr)
}

// array_at borrows element `i`.
pub fn array_at(arr voidptr, i i64) voidptr {
	p := sym(cf_lib(), c'CFArrayGetValueAtIndex')
	if p == unsafe { nil } || arr == unsafe { nil } {
		return unsafe { nil }
	}
	f := unsafe { FnAt(p) }
	return f(arr, i)
}

pub fn number_i64(num voidptr) ?i64 {
	if !is_number(num) {
		return none
	}
	p := sym(cf_lib(), c'CFNumberGetValue')
	if p == unsafe { nil } {
		return none
	}
	f := unsafe { FnNumGet(p) }
	mut out := i64(0)
	if f(num, cf_number_sint64, voidptr(&out)) == 0 {
		return none
	}
	return out
}

pub fn number_f64(num voidptr) ?f64 {
	if !is_number(num) {
		return none
	}
	p := sym(cf_lib(), c'CFNumberGetValue')
	if p == unsafe { nil } {
		return none
	}
	f := unsafe { FnNumGet(p) }
	mut out := f64(0)
	if f(num, cf_number_float64, voidptr(&out)) == 0 {
		return none
	}
	return out
}

pub fn boolean(b voidptr) bool {
	if b == unsafe { nil } {
		return false
	}
	p := sym(cf_lib(), c'CFBooleanGetValue')
	if p == unsafe { nil } {
		return false
	}
	f := unsafe { FnBool1(p) }
	return f(b) != 0
}

pub fn equal(a voidptr, b voidptr) bool {
	if a == unsafe { nil } || b == unsafe { nil } {
		return false
	}
	p := sym(cf_lib(), c'CFEqual')
	if p == unsafe { nil } {
		return false
	}
	f := unsafe { FnBool2(p) }
	return f(a, b) != 0
}

// equal_str compares a CF value with a V string.
pub fn equal_str(obj voidptr, s string) bool {
	k := cfstr(s)
	defer {
		release(k)
	}
	return equal(obj, k)
}

pub fn data_bytes(data voidptr) []u8 {
	if !is_data(data) {
		return []u8{}
	}
	plen := sym(cf_lib(), c'CFDataGetLength')
	pptr := sym(cf_lib(), c'CFDataGetBytePtr')
	if plen == unsafe { nil } || pptr == unsafe { nil } {
		return []u8{}
	}
	flen := unsafe { FnCount(plen) }
	fptr := unsafe { FnBytes(pptr) }
	n := flen(data)
	base := fptr(data)
	if n <= 0 || base == unsafe { nil } {
		return []u8{}
	}
	mut out := []u8{len: int(n)}
	for i in 0 .. int(n) {
		out[i] = unsafe { base[i] }
	}
	return out
}

// to_string reads a CFString, or a CFData holding a NUL-terminated C
// string (the IORegistry spells PCI "model" that way) — fastfetch's
// ffCfStrGetString. none for anything else.
pub fn to_string(obj voidptr) ?string {
	if obj == unsafe { nil } {
		return none
	}
	if is_data(obj) {
		bytes := data_bytes(obj)
		mut n := 0
		for n < bytes.len && bytes[n] != 0 {
			n++
		}
		if n == 0 {
			return none
		}
		return bytes[..n].bytestr()
	}
	if !is_string(obj) {
		return none
	}
	p := sym(cf_lib(), c'CFStringGetCString')
	if p == unsafe { nil } {
		return none
	}
	f := unsafe { FnStrGet(p) }
	mut buf := []u8{len: 1024}
	if f(obj, buf.data, i64(buf.len), cf_utf8) == 0 {
		return none
	}
	mut n := 0
	for n < buf.len && buf[n] != 0 {
		n++
	}
	return buf[..n].bytestr()
}

// dict_string / dict_i64 read one typed value out of a dictionary.
pub fn dict_string(dict voidptr, key string) ?string {
	return to_string(dict_get(dict, key))
}

pub fn dict_i64(dict voidptr, key string) ?i64 {
	return number_i64(dict_get(dict, key))
}

// pref copies a value out of an app's preferences domain (the user's
// ~/Library/Preferences/<app>.plist through cfprefsd); release it.
pub fn pref(key string, app string) voidptr {
	p := sym(cf_lib(), c'CFPreferencesCopyAppValue')
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	k := cfstr(key)
	a := cfstr(app)
	defer {
		release(k)
		release(a)
	}
	if k == unsafe { nil } || a == unsafe { nil } {
		return unsafe { nil }
	}
	f := unsafe { FnGet2(p) }
	return f(k, a)
}

// plist_from_data parses a (binary or XML) property list held in a
// CFData; release the result.
pub fn plist_from_data(data voidptr) voidptr {
	if !is_data(data) {
		return unsafe { nil }
	}
	p := sym(cf_lib(), c'CFPropertyListCreateWithData')
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	f := unsafe { FnPlist(p) }
	return f(unsafe { nil }, data, 0, unsafe { nil }, unsafe { nil })
}

// uid_value reads an NSKeyedArchiver object reference (CF$UID).
pub fn uid_value(uid voidptr) ?u32 {
	if !is_uid(uid) {
		return none
	}
	p := sym(cf_lib(), c'_CFKeyedArchiverUIDGetValue')
	if p == unsafe { nil } {
		return none
	}
	f := unsafe { FnUid(p) }
	return f(uid)
}

// ─── IOKit ─────────────────────────────────────────────────────────────

type FnMatching = fn (&char) voidptr

type FnGetServices = fn (u32, voidptr, &u32) i32

type FnGetService = fn (u32, voidptr) u32

type FnNext = fn (u32) u32

type FnProps = fn (u32, &voidptr, voidptr, u32) i32

type FnParent = fn (u32, &char, &u32) i32

type FnObjRelease = fn (u32) i32

type FnOpen = fn (u32, u32, u32, &u32) i32

type FnClose = fn (u32) i32

type FnCallStruct = fn (u32, u32, voidptr, u64, voidptr, &u64) i32

type FnVoidRet = fn () voidptr

type FnDesc = fn (voidptr, voidptr) voidptr

type FnGet1 = fn (voidptr) voidptr

pub fn io_release(obj u32) {
	if obj == 0 {
		return
	}
	p := sym(iokit_lib(), c'IOObjectRelease')
	if p == unsafe { nil } {
		return
	}
	f := unsafe { FnObjRelease(p) }
	f(obj)
}

// matching builds an IOServiceMatching dictionary for `class`; the
// IOServiceGetMatching* calls consume it.
pub fn matching(class string) voidptr {
	p := sym(iokit_lib(), c'IOServiceMatching')
	if p == unsafe { nil } {
		return unsafe { nil }
	}
	f := unsafe { FnMatching(p) }
	return f(&char(class.str))
}

// services lists the registry entries `dict` matches (consumed); the
// caller io_releases each.
pub fn services(dict voidptr) []u32 {
	mut out := []u32{}
	if dict == unsafe { nil } {
		return out
	}
	pget := sym(iokit_lib(), c'IOServiceGetMatchingServices')
	pnext := sym(iokit_lib(), c'IOIteratorNext')
	if pget == unsafe { nil } || pnext == unsafe { nil } {
		return out
	}
	get := unsafe { FnGetServices(pget) }
	next := unsafe { FnNext(pnext) }
	mut iter := u32(0)
	if get(0, dict, &iter) != 0 || iter == 0 {
		return out
	}
	for {
		entry := next(iter)
		if entry == 0 {
			break
		}
		out << entry
	}
	io_release(iter)
	return out
}

// service answers the first entry `dict` matches (consumed), 0 for none.
pub fn service(dict voidptr) u32 {
	if dict == unsafe { nil } {
		return 0
	}
	p := sym(iokit_lib(), c'IOServiceGetMatchingService')
	if p == unsafe { nil } {
		return 0
	}
	f := unsafe { FnGetService(p) }
	return f(0, dict)
}

// properties copies an entry's whole property table; release it.
pub fn properties(entry u32) voidptr {
	p := sym(iokit_lib(), c'IORegistryEntryCreateCFProperties')
	if p == unsafe { nil } || entry == 0 {
		return unsafe { nil }
	}
	f := unsafe { FnProps(p) }
	mut out := unsafe { nil }
	if f(entry, &out, unsafe { nil }, 0) != 0 {
		return unsafe { nil }
	}
	return out
}

// parent answers the entry's IOService-plane parent (io_release it), 0
// for none.
pub fn parent(entry u32) u32 {
	p := sym(iokit_lib(), c'IORegistryEntryGetParentEntry')
	if p == unsafe { nil } || entry == 0 {
		return 0
	}
	f := unsafe { FnParent(p) }
	mut out := u32(0)
	if f(entry, c'IOService', &out) != 0 {
		return 0
	}
	return out
}

// ─── power sources (IOPS*, the keys pmset(1) prints) ───────────────────

pub struct Battery {
pub:
	percent int
	status  string
}

// battery answers the first internal battery, modules/zig/macos.zig's
// battery() line for line: charge rounded from Current/Max Capacity and
// the linux status words.
pub fn battery() ?Battery {
	lib := iokit_lib()
	pinfo := sym(lib, c'IOPSCopyPowerSourcesInfo')
	plist := sym(lib, c'IOPSCopyPowerSourcesList')
	pdesc := sym(lib, c'IOPSGetPowerSourceDescription')
	if pinfo == unsafe { nil } || plist == unsafe { nil } || pdesc == unsafe { nil } {
		return none
	}
	copy_info := unsafe { FnVoidRet(pinfo) }
	copy_list := unsafe { FnGet1(plist) }
	describe := unsafe { FnDesc(pdesc) }
	info := copy_info()
	if info == unsafe { nil } {
		return none
	}
	defer {
		release(info)
	}
	list := copy_list(info)
	if list == unsafe { nil } {
		return none
	}
	defer {
		release(list)
	}
	for i in 0 .. array_count(list) {
		ps := array_at(list, i)
		if ps == unsafe { nil } {
			continue
		}
		desc := describe(info, ps) // borrowed
		if desc == unsafe { nil } || !equal_str(dict_get(desc, 'Type'), 'InternalBattery') {
			continue
		}
		cur := dict_i64(desc, 'Current Capacity') or { continue }
		mut max := dict_i64(desc, 'Max Capacity') or { 100 }
		if max <= 0 {
			max = 100
		}
		clamped := if cur < 0 { i64(0) } else { cur }
		mut percent := int((clamped * 100 + max / 2) / max)
		if percent > 100 {
			percent = 100
		}
		on_ac := equal_str(dict_get(desc, 'Power Source State'), 'AC Power')
		status := if boolean(dict_get(desc, 'Is Charging')) {
			'Charging'
		} else if !on_ac {
			'Discharging'
		} else if boolean(dict_get(desc, 'Is Charged')) || percent >= 100 {
			'Full'
		} else {
			'Not charging' // optimized charging holds at 80% on AC
		}
		return Battery{
			percent: percent
			status:  status
		}
	}
	return none
}

// ─── SMC (fastfetch common/apple/smc_temps.c) ──────────────────────────
// SmcKeyData_t is 80 bytes: key u32 @0, keyInfo.dataSize u32 @28,
// keyInfo.dataType u32 @32, data8 @42, bytes[32] @48.

const smc_cmd_read_bytes = u8(5)
const smc_cmd_read_key_info = u8(9)
const smc_cmd_read_index = u8(8) // key at data32 = index (smcFanControl's SMC_CMD_READ_INDEX)
const smc_kernel_index = u32(2)

pub struct Smc {
	conn u32
}

// smc_open opens the AppleSMC user client; close() it.
pub fn smc_open() ?Smc {
	dev := service(matching('AppleSMC'))
	if dev == 0 {
		return none
	}
	defer {
		io_release(dev)
	}
	popen := sym(iokit_lib(), c'IOServiceOpen')
	task_ptr := C.dlsym(rtld_default, c'mach_task_self_')
	if popen == unsafe { nil } || task_ptr == unsafe { nil } {
		return none
	}
	task := unsafe { *(&u32(task_ptr)) }
	open := unsafe { FnOpen(popen) }
	mut conn := u32(0)
	if open(dev, task, 0, &conn) != 0 || conn == 0 {
		return none
	}
	return Smc{
		conn: conn
	}
}

pub fn (s Smc) close() {
	p := sym(iokit_lib(), c'IOServiceClose')
	if p == unsafe { nil } {
		return
	}
	f := unsafe { FnClose(p) }
	f(s.conn)
}

fn put_u32(mut b []u8, off int, v u32) {
	b[off] = u8(v)
	b[off + 1] = u8(v >> 8)
	b[off + 2] = u8(v >> 16)
	b[off + 3] = u8(v >> 24)
}

fn get_u32(b []u8, off int) u32 {
	return u32(b[off]) | (u32(b[off + 1]) << 8) | (u32(b[off + 2]) << 16) | (u32(b[off + 3]) << 24)
}

fn (s Smc) call(input []u8) ?[]u8 {
	p := sym(iokit_lib(), c'IOConnectCallStructMethod')
	if p == unsafe { nil } {
		return none
	}
	f := unsafe { FnCallStruct(p) }
	mut output := []u8{len: 80}
	mut size := u64(80)
	if f(s.conn, smc_kernel_index, input.data, u64(80), output.data, &size) != 0 {
		return none
	}
	return output
}

// read decodes one 4-char SMC key into a number; none for a missing key
// or a type fastfetch doesn't decode either.
pub fn (s Smc) read(key string) ?f64 {
	if key.len != 4 {
		return none
	}
	code := (u32(key[0]) << 24) | (u32(key[1]) << 16) | (u32(key[2]) << 8) | u32(key[3])
	mut input := []u8{len: 80}
	put_u32(mut input, 0, code)
	input[42] = smc_cmd_read_key_info
	info := s.call(input) or { return none }
	size := get_u32(info, 28)
	dtype := get_u32(info, 32)
	if size == 0 || size > 32 {
		return none
	}
	put_u32(mut input, 28, size)
	input[42] = smc_cmd_read_bytes
	out := s.call(input) or { return none }
	b := out[48..80]
	t0 := u8(dtype >> 24)
	t1 := u8(dtype >> 16)
	t2 := u8(dtype >> 8)
	t3 := u8(dtype)
	be16 := (u32(b[0]) << 8) | u32(b[1])
	if t0 == `f` && t1 == `l` && t2 == `t` && size == 4 {
		bits := get_u32(b, 0) // native-endian float
		return f64(unsafe { *(&f32(voidptr(&bits))) })
	}
	if (t0 == `f` || t0 == `s`) && t1 == `p` && size == 2 {
		// fpXY / spXY: Y hex digits of fraction — divisor 2^Y
		frac := hex_digit(t3) or { return none }
		raw := if t0 == `s` { f64(i16(u16(be16))) } else { f64(be16) }
		return raw / f64(u32(1) << frac)
	}
	if (t0 == `u` || t0 == `s`) && t1 == `i` {
		match size {
			1 {
				return if t0 == `s` { f64(i8(b[0])) } else { f64(b[0]) }
			}
			2 {
				return if t0 == `s` { f64(i16(u16(be16))) } else { f64(be16) }
			}
			4 {
				v := (u32(b[0]) << 24) | (u32(b[1]) << 16) | (u32(b[2]) << 8) | u32(b[3])
				return if t0 == `s` { f64(i32(v)) } else { f64(v) }
			}
			else {
				return none
			}
		}
	}
	return none
}

// key_count answers the SMC's "#KEY" entry, how many keys key_at walks.
pub fn (s Smc) key_count() int {
	n := s.read('#KEY') or { return 0 }
	return int(n)
}

// key_at answers the 4-char name of the SMC key at `index`.
pub fn (s Smc) key_at(index int) ?string {
	mut input := []u8{len: 80}
	input[42] = smc_cmd_read_index
	put_u32(mut input, 44, u32(index))
	out := s.call(input) or { return none }
	if out[40] != 0 {
		return none
	}
	code := get_u32(out, 0)
	return [u8(code >> 24), u8(code >> 16), u8(code >> 8), u8(code)].bytestr()
}

fn hex_digit(c u8) ?u32 {
	if c >= `0` && c <= `9` {
		return u32(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return u32(c - `a` + 10)
	}
	return none
}

// ─── sysctl ────────────────────────────────────────────────────────────

// sysctl_string reads a string sysctl such as machdep.cpu.brand_string.
pub fn sysctl_string(name string) ?string {
	mut buf := []u8{len: 256}
	mut n := uint(buf.len)
	if unsafe { C.sysctlbyname(&char(name.str), buf.data, &n, nil, 0) } != 0 || n > uint(buf.len) {
		return none
	}
	mut end := 0
	for end < int(n) && buf[end] != 0 {
		end++
	}
	return buf[..end].bytestr()
}
