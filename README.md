# [ divifetch ]

> *an anti-fetch script generator with mostly hard-coded values, dynamic modules and optimisations*

## >> WHAT? >>

divifetch is a build-time fetch script compiler.

it reads a simple config file and generates a C program that renders ASCII art with dynamic content from pluggable modules.

unlike other fetch scripts that parse configs and fork processes at every run, divifetch moves most of the work to compile time - producing a binary that's faster, smaller, and dependency-freer than any traditional fetch script could be.

## >> FEATURES >>

- everything is hard-coded and statically batched
- strict no dead code policy (only used modules and headers are included)
- Unicode and ANSI escape code support
- easily extensible module system

## >> GETTING STARTED >>

```shell
# clone the repo:
git clone https://git.divio.city/diviocity/divifetch.git
cd divifetch

# compile the generator:
g++ -std=c++17 -o generator generator.cpp 

# generate, copy and edit the example config file:
./generator config
cp config.conf.example config.conf
vi config.conf

# compile the fetch script and run it:
gcc -O2 -static -s -o divifetch fetch.c
./divifetch
```

## >> SCREENSHOT >>

![diviocity](https://divio.city/toolchain/meow.png)

## >> COMING SOON >>

- more modules

- improved error handling

- proper config format for modules

- bindings for other programming languages in modules

## >> MOTIVATION >>

divifetch is inspired by [nofetch](https://github.com/0xCUB3/nofetch), the world's fastest fetch script ever made. according to its' author:
> fetch scripts are dumb and overrated and are in every r/unixporn post

and i agree with him.

the concept of a "fetch script" itself is flawed - it implies that trying to optimize fetching large amounts of unnecessary information (which never or almost never changes) is going to make much performance difference.

one might try to circumvent this by hard-coding values into the config file, but even then the fetch script is still reading a useless config file and assembling every module/entry on the file.

unfortunately for me, i do enjoy the aesthetic value that having something (including a fetch script) on shell startup brings. that led to me creating divifetch.

Mirrors:
[diviocity](https://git.divio.city/diviocity/divifetch)
[disroot](https://git.disroot.org/diviocity/divifetch)
[codeberg](https://codeberg.org/diviocity/divifetch)
[github](https://github.com/diiviocity/divifetch)
[gitlab](https://gitlab.com/diiviocity/divifetch)
