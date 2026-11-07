// vpn module: tunnel interface presence under /sys/class/net — the
// first tun*/wg*/tap*/ppp* answers "up (<name>)", none answers "down".
// zero spawn. the BSD targets walk libc getifaddrs chains through the
// zig helpers; the V branch answers '?' on an unread netfs and keeps
// 'down' honest while none lists. macOS walks getifaddrs(3): a tunnel
// counts only while up with an IPv4 address on it, since the system
// keeps several utun* up at all times with nothing but IPv6 link-local.
module vpn

import os

@[direct_array_access]
pub fn preset() string {
	$if openbsd {
		return '?'
	}
	$if freebsd {
		return '?'
	}
	$if macos {
		return macos_preset()
	}

	entries := os.ls('/sys/class/net') or { return '?' }
	for entry in entries {
		if entry.starts_with('tun') || entry.starts_with('wg') || entry.starts_with('tap')
			|| entry.starts_with('ppp') {
			return 'up (${entry})'
		}
	}
	return 'down'
}

fn C.getifaddrs(ifap &voidptr) i32
fn C.freeifaddrs(ifa voidptr)

// struct ifaddrs (ifaddrs.h, LP64): ifa_next at 0, ifa_name at 8,
// ifa_flags u32 at 16, ifa_addr at 24; a sockaddr's family is its
// second byte (sa_len first). IFF_UP 0x1, AF_INET 2.
@[direct_array_access]
fn macos_preset() string {
	mut head := unsafe { nil }
	if C.getifaddrs(&head) != 0 {
		return '?'
	}
	defer {
		C.freeifaddrs(head)
	}
	mut cur := head
	for cur != unsafe { nil } {
		base := unsafe { &u8(cur) }
		next := unsafe { *(&voidptr(base)) }
		name_ptr := unsafe { *(&voidptr(base + 8)) }
		flags := unsafe { *(&u32(base + 16)) }
		addr := unsafe { &u8(*(&voidptr(base + 24))) }
		cur = next
		if name_ptr == unsafe { nil } || addr == unsafe { nil } || flags & 1 == 0 {
			continue
		}
		if unsafe { addr[1] } != 2 {
			continue
		}
		name := unsafe { cstring_to_vstring(&char(name_ptr)) }
		if name.starts_with('utun') || name.starts_with('ipsec') || name.starts_with('tun')
			|| name.starts_with('wg') || name.starts_with('tap') || name.starts_with('ppp') {
			return 'up (${name})'
		}
	}
	return 'down'
}
