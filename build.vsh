#!/usr/bin/env -S v run

/* temporary minimal build script */

import build

mut context := build.context(default: 'generator')

context.task(name: 'generator', run: fn (self build.Task) ! {
    system('v -n -w -o ./generator ./src/generator')
    println('built ./generator')
})

context.run()
