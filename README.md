# [ divifetch ]

> *an anti-fetch script generator with mostly hard-coded values, dynamic modules and optimisations*

![diviocity](screenshots/diviocity.png)

## >> WHAT? >>

divifetch is a build-time fetch script compiler.

it reads a simple config file and generates a Zig program that renders ASCII art with dynamic content from pluggable modules.

unlike other fetch scripts that parse configs and fork processes at every run, divifetch moves most of the work to compile time - producing a binary that's faster, smaller, and dependency-freer than any traditional fetch script could be.

## >> FEATURES >>

- everything is hard-coded and statically batched
- strict no dead code policy
- runtime dependency-free due to static linking
- easily extensible module system
- polyglot module support (C, C++, Rust, D, V)
- multi-config random selection
- Unicode and ANSI escape code support

## >> PREREQUISITES >>

- [V](https://vlang.io/) compiler (0.5.2)
- [Zig](https://ziglang.org/) compiler (0.17.x)
- [blip](https://git.vorelabs.dev/vorelabs/blip) machine

## >> GETTING STARTED >>

```shell
# clone the repo
git clone https://git.vorelabs.dev/vorelabs/divifetch.git
cd divifetch

# generate an example config file
v run generator -C

# generate the source code, build script and run it
v run generator

# run the generated fetch
./target/divifetch
```

## >> SCREENSHOTS >>

can be found [here](screenshots/README.md)

## >> DOCUMENTATION >>

can be found [here](https://git.vorelabs.dev/vorelabs/divifetch/wiki)

(outdated as of v4.0)

## >> MOTIVATION >>

divifetch is inspired by [nofetch](https://github.com/0xCUB3/nofetch), the world's fastest fetch script ever made. according to its author:
> fetch scripts are dumb and overrated and are in every r/unixporn post

and i agree with him.

the concept of a "fetch script" itself is flawed - it implies that trying to optimize fetching large amounts of unnecessary information (which never or almost never changes) is going to make much performance difference.

one might try to circumvent this by hard-coding values into the config file, but even then the fetch script is still reading a useless config file and assembling every module/entry on the file.

unfortunately for me, i do enjoy the aesthetic value that having something (including a fetch script) on shell startup brings. that led to me creating divifetch.

Mirrors:
[diviocity](https://git.vorelabs.dev/vorelabs/divifetch)
[disroot](https://git.disroot.org/diviocity/divifetch)
[codeberg](https://codeberg.org/diviocity/divifetch)
[git.gay](https://git.gay/diviocity/divifetch)
[gitea](https://gitea.com/diviocity/divifetch)
[rocketgit](https://rocketgit.com/user/diviocity/divifetch)
[salsa](https://salsa.debian.org/diviocity/divifetch)
[framagit](https://framagit.org/diviocity/divifetch)
[gitlab](https://gitlab.com/diiviocity/divifetch)
[github](https://github.com/diiviocity/divifetch)

