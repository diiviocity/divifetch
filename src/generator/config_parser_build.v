pub struct BuildConfig {
	mut:
	exec             string = "#!/usr/bin/env -S v run"
	cc               string
	cflags           string
	target           string = "divifetch"
	target_head      string = "headgen"
	dest_dir         string = "/usr/local/bin"
	build_dir        string = "target"
	custom           string
	default          string = "crun"
	source_file      string
	command          string
	linker_flags     string
	object_extension string
	archive          string
}

pub struct BuildTemplate {
	mut:
	name             string
	source_file      string
	command          string
	linker_flags     string
	object_extension string
	archive          string
}

const pos_build = ['name', 'source_file', 'command', 'linker_flags', 'object_extension', 'archive']

fn parse_build_templates_config(filename string, mut config BuildConfig, mut templates map[string]BuildTemplate) {
	mut tokens, mut idx := config_parser_reader_tokenizer(filename), 0
	for idx < tokens.len {
		form, new_idx := config_parser_form_reader(tokens, idx)
		idx = new_idx
		if form.len == 0 { break }
		if form[0] == 'config' {
			reflect_form(mut config, form, filename)
        } else if form[0] == 'template' {
            mut tmpl := reflect_struct[BuildTemplate, BuildConfig](config)
			reflect_form_pos(mut tmpl, form, pos_build, filename)
            templates[tmpl.name] = tmpl
        }
    }
}

fn parse_build_module_config(filename string, templates map[string]BuildTemplate, mut tmpl BuildTemplate) {
	tmpl = templates['c']
	mut tokens, mut idx := config_parser_reader_tokenizer(filename), 0
	for idx < tokens.len {
		form, new_idx := config_parser_form_reader(tokens, idx)
		idx = new_idx
		if form.len == 0 { break }
        if form[0] == 'language' {
			if form.len != 2 { print_syntax_error(form, filename) }
            if !(form[1] in templates) { print_error('no template \'${form[1]}\' in the build config (referenced in ${filename})') }
            tmpl = templates[form[1]]
		} else if form[0] == 'template' {
			reflect_form_pos(mut tmpl, form, pos_build, filename)
		}
    }
}
