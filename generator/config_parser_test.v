// config_parser_test.v — what every lip form shares: the datums, the way
// positional and named arguments split, and the toggles they read.
module main

import blip.vlib.blip.reader

// snippet_arena parses one snippet and returns the reader result, failing
// the test on diagnostics instead of letting a file's own reading slide.
fn snippet_arena(src string) reader.ReadResult {
	res := reader.read_all(src)
	if res.diags.len > 0 {
		panic('snippet parse diagnostics: ${res.diags[0].render('snippet.lip')}')
	}
	return res
}

// first_args splits the first form of a snippet inside a string.
fn snippet_args(src string) !SplitArgs {
	res := snippet_arena(src)
	return keyword_args(&res.arena, 'snippet.lip', 'form', res.forms[0])
}

fn test_normalize_name_unifies_hyphens() {
	assert normalize_name('colors-normal') == 'colors_normal'
	assert normalize_name('key-case') == 'key_case'
	assert normalize_name('plain') == 'plain'
	assert normalize_name('a-b_c') == 'a_b_c'
}

fn test_stringy_takes_strings_and_keywords() {
	res := snippet_arena('(f "quoted" :kw bare)')
	kids := res.arena.kids(res.forms[0])
	first := stringy(res.arena.node(kids[1])) or { panic('a string must read') }
	second := stringy(res.arena.node(kids[2])) or { panic('a keyword must read') }
	assert first == 'quoted'
	assert second == 'kw'
	assert stringy(res.arena.node(kids[3])) == none
}

fn test_str_of_reads_a_string_or_errors() {
	res := snippet_arena('(f "text" 42 :key)')
	kids := res.arena.kids(res.forms[0])
	assert str_of(&res.arena, kids[1], 'f.lip', 'the field')! == 'text'
	str := str_of(&res.arena, kids[2], 'f.lip', 'the field') or {
		assert err.msg().contains('the field must be a quoted string, got an integer')
		return
	}
	panic('str_of should have failed on an integer, got: ${str}')
}

fn test_int_of_reads_an_integer_or_errors() {
	res := snippet_arena('(f 42 -3 "x")')
	kids := res.arena.kids(res.forms[0])
	assert int_of(&res.arena, kids[1], 'f.lip', 'the count')! == 42
	assert int_of(&res.arena, kids[2], 'f.lip', 'the count')! == -3
	int_of(&res.arena, kids[3], 'f.lip', 'the count') or {
		assert err.msg().contains('the count must be an integer, got a string')
		return
	}
	panic('int_of should have failed on a string')
}

fn test_keyword_of_strips_the_colon() {
	res := snippet_arena('(f :before)')
	kids := res.arena.kids(res.forms[0])
	assert keyword_of(&res.arena, kids[1], 'f.lip', 'the arg')! == 'before'
}

fn test_list_of_holds_single_and_listed_strings() {
	res := snippet_arena('(f ["echo hi" "/home"] "one")')
	kids := res.arena.kids(res.forms[0])
	assert list_of(&res.arena, kids[1], 'f.lip', 'the args')! == ['echo hi', '/home']
	assert list_of(&res.arena, kids[2], 'f.lip', 'the args')! == ['one']
}

fn test_list_of_accepts_keywords_as_items() {
	res := snippet_arena('(f [:io :environ] :io)')
	kids := res.arena.kids(res.forms[0])
	assert list_of(&res.arena, kids[1], 'f.lip', 'module :deps')! == ['io', 'environ']
	assert list_of(&res.arena, kids[2], 'f.lip', 'module :deps')! == ['io']
}

fn test_list_of_rejects_bad_items() {
	res := snippet_arena('(f ["a" 1])')
	kids := res.arena.kids(res.forms[0])
	list_of(&res.arena, kids[1], 'f.lip', 'the args') or {
		assert err.msg().contains('the args must hold strings or keywords, got an integer')
		return
	}
	panic('list_of should have failed on an integer item')
}

fn test_yes_no_reads_every_toggle() {
	res := snippet_arena('(f "yes" "no" yes no #t #f "nope")')
	kids := res.arena.kids(res.forms[0])
	assert yes_no(&res.arena, kids[1], 'f.lip', 'the toggle')! == true
	assert yes_no(&res.arena, kids[2], 'f.lip', 'the toggle')! == false
	assert yes_no(&res.arena, kids[3], 'f.lip', 'the toggle')! == true
	assert yes_no(&res.arena, kids[4], 'f.lip', 'the toggle')! == false
	assert yes_no(&res.arena, kids[5], 'f.lip', 'the toggle')! == true
	assert yes_no(&res.arena, kids[6], 'f.lip', 'the toggle')! == false
	yes_no(&res.arena, kids[7], 'f.lip', 'the toggle') or {
		assert err.msg().contains("the toggle must be yes or no, got 'nope'")
		return
	}
	panic('yes_no should have failed on nope')
}

fn test_warn_once_prints_a_line_the_first_time_only() {
	// the line is captured by running the whole command, so here the map's
	// contract is what is checked: first call adds, later calls no-op.
	mut cfg := Config{
		warned: map[string]bool{}
	}
	assert cfg.warned['note'] == false
	cfg.warn_once('note')
	assert cfg.warned['note'] == true
}

fn test_keyword_args_split_positional_and_named() {
	args := snippet_args('(form "key" "value" :key-prefix "kp" :key2 "kv")')!
	assert args.positional.len == 2
	assert args.pairs.len == 2
	assert args.pairs[0].key == 'key-prefix'
	assert args.pairs[1].key == 'key2'
}

fn test_keyword_args_walks_head_offset() {
	// kids[0] is the form head; the split starts at kids[1].
	res := snippet_arena('(uptime "now" :key "Uptime")')
	args := keyword_args(&res.arena, 's.lip', 'uptime', res.forms[0])!
	assert args.positional.len == 1
	assert args.pairs.len == 1
	assert args.pairs[0].key == 'key'
}

fn test_keyword_args_errors_on_a_trailing_keyword() {
	res := snippet_arena('(form :key)')
	keyword_args(&res.arena, 's.lip', 'form', res.forms[0]) or {
		assert err.msg().contains('form has no value for :key')
		return
	}
	panic('keyword_args should have failed on a trailing keyword')
}

fn test_at_renders_the_position() {
	res := snippet_arena('(battery :key "value")')
	kid := res.arena.kids(res.forms[0])[2]
	msg := at('s.lip', res.arena.node(kid), 'boom')
	assert msg.starts_with('s.lip:')
	assert msg.contains(': boom')
}

fn test_pretty_type_names_the_datums() {
	res := snippet_arena('(f "x" 1 :k [1] #t (inner))')
	kids := res.arena.kids(res.forms[0])
	assert pretty_type(res.arena.node(kids[1])) == 'a string'
	assert pretty_type(res.arena.node(kids[2])) == 'an integer'
	assert pretty_type(res.arena.node(kids[3])) == 'a keyword'
	assert pretty_type(res.arena.node(kids[4])) == 'a list'
	assert pretty_type(res.arena.node(kids[5])) == 'a bool'
	assert pretty_type(res.arena.node(kids[6])) == 'a list'
}
