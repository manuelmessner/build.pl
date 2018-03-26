# build.pl

Build everything with only one command using rules defined in a yaml
configuration file.

Build order:

1. execute `command_file` if it exists instead of normal build process.
1. execute `make` if a `Makefile` exists instead of normal build process.
1. depending on your configuration execute specified rules or execute a shebang.


## Dependencies:

For `build.pl`:

* `File::Basename` (basename, fileparse)
* `Getopt::ArgParse`
* `IO::CaptureOutput` (capture)
* `Text::ParseWords`
* `YAML`

For `cincs.pl`:

* `Cwd` (realpath)
* `File::Basename`


## Installation

Place `build.pl` and `cincs.pl` somewhere within the `$PATH`.
`cincs.pl` may be exchanged by another similar tool.

To setup the vim plugin, copy `build.vim` to `$HOME/.vim/build/build.vim`.

## Configuration File:

The configuration file can be in one of the following places:

* `$HOME/.config/build/config.yml`
* `$HOME/.config/build/config.yaml`
* `$HOME/.buildrc`
* `/etc/build.yml`
* `/etc/build.yaml`

See `examples/build.yml` for an example.

`inc_cmd` specifies the path to an application which collects all files that
need to be passed to a compiler.
Currently supported in `cincs.pl`:

* C
* C++
* D

## Usage:

### build.pl:

```bash
usage: build.pl [FILE] [--help|-h] [--method|-M] [--run-only|-r]
[--build-only|-b] [--silent|-s] [--verbose|-v] [--no-makefile|-n] [--makefile]
[--replace-definitions|-R] [--extend-definitions|-E] [--no-command-file]
[--command-file|-f] [--interactive|-i] [--out-file|-o] [--mode|-m] [--release]
[--debug] [--language|-l]

Builds and runs projects

optional positional arguments:
  FILE          ? File to build and/or execute

optional named arguments:
  --help, -h                                       ? show this help message and exit
  --method, -M METHOD                              ? Specify and use given method to build/run instead of
                                                       predefinitions
  --run-only, -r                                   ? Just run the application and do not build it
  --build-only, -b                                 ? Just build the application and do not run it
  --silent, -s                                     ? No additional output - only output from executed file
  --verbose, -v                                    ? Verbose output
  --no-makefile, -n                                ? Do not use the Makefile if it exists
  --makefile MAKEFILE                              ? Specify and use given alternative makefile instead of
                                                       predefinitions
  --replace-definitions, -R REPLACE-DEFINITIONS    ? Replace predefinitions with rules from given file
  --extend-definitions, -E EXTEND-DEFINITIONS      ? Extend predefinitions with rules from given file
  --no-command-file                                ? Do not use the command file if it exists
  --command-file, -f COMMAND-FILE                  ? Specify and use given alternative command file instead of
                                                       predefinitions
  --interactive, -i                                ? Do not capture any output; allow interactive debugging
                                                       sessions
  --out-file, -o OUT-FILE                          ? Specify and use an alternative output filename
  --mode, -m MODE                                  ? Specify build mode
                                                       Choices: [d, debug, r, release], case sensitive
  --release                                        ? Build in release mode (alternative for `-m release`)
  --debug                                          ? Build in debug mode (alternative for `-m debug`)
  --language, -l LANGUAGE                          ? Disable language auto detection and use the given one
                                                       Choices: [bash, c, cpp, d, dash, fish, haskell, idris,
                                                       javascript, lua, moonscript, nim, pdf, perl, php, pure,
                                                       python, python2, python3, racket, ruby, rust, scheme, sent,
                                                       sh, svg, uml], case sensitive
```

### vim-plugin:

The vim plugin exports three commands:

* `Build`: base command
* `DBuild`: performs a debug build
* `RBuild`: performs a release build

