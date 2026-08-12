pub struct SourceConfig {
	mut:
	buffer_size  int    = 128
	execute      string
	art_width    int    = -1
	art_padding  int    = 3
	art_file     string
	art_prefix   string
	art_suffix   string
	type         string
	key_prefix   string
	key_suffix   string
	value        string
	value_prefix string
	value_suffix string
	build_time   string
	key_case     string = "first"
	underscore   string = " "
	new_print    string
}

pub struct SourceEntry {
	mut:
	type         string
	key          string
	key_prefix   string
	key_suffix   string
	value        string
	value_prefix string
	value_suffix string
	build_time   string
	key_case     string
	underscore   string
	new_print    string
}

pub struct ConfigSource {
	mut:
	entries []SourceEntry
	config  SourceConfig
}

const source_pos = ['key', 'value', 'key_prefix', 'key_suffix', 'value_prefix', 'value_suffix']

fn parse_source_config(filename string, mut source ConfigSource) {
	mut tokens, mut idx := config_parser_reader_tokenizer(filename), 0
	for idx < tokens.len {
		form, new_idx := config_parser_form_reader(tokens, idx)
		idx = new_idx
		if form.len == 0 { break }
		if form[0] == 'config' {
			reflect_form(mut source.config, form, filename)
		} else {
			mut entry := reflect_struct[SourceEntry, SourceConfig](source.config)
			entry.type, entry.value = form[0], ''
			entry.key = if      entry.key_case == "lower" { form[0].to_lower().replace('_', entry.underscore) }
			            else if entry.key_case == "upper" { form[0].to_upper().replace('_', entry.underscore) }
			            else if entry.key_case == "first" { form[0].title().replace('_', entry.underscore) }
			            else if entry.key_case == "title" { form[0].replace('_', ' ').title().replace(' ', entry.underscore) }
				        else {
							print_error('unknown key case: ${entry.key_case} (referenced in ${filename})')
							''
						}

			if entry.type == 'break' {
				entry.type, entry.key = 'plain', ''
			} else if entry.type == 'colors_normal' {
				entry.type, entry.key = 'plain', '\\033[40m   \\033[41m   \\033[42m   \\033[43m   \\033[44m   \\033[45m   \\033[46m   \\033[47m   \\033[0m'
			} else if entry.type == 'colors_bright' {
				entry.type, entry.key = 'plain', '\\033[100m   \\033[101m   \\033[102m   \\033[103m   \\033[104m   \\033[105m   \\033[106m   \\033[107m   \\033[0m'
			}
			if entry.type == 'plain' {
				entry.type, entry.key_prefix, entry.key_suffix, entry.value_prefix, entry.value_suffix = 'static', '', '', '', ''
			}

			reflect_form_pos(mut entry, form, source_pos, filename)
			source.entries << entry
		}
	}
}
