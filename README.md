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
usage: build.pl FILE [--help|-h] [--run-only] [--build-only] [--silent|-s]
                     [--verbose|-v] [--no-makefile] [--makefile] [--replace-definitions|-r]
                     [--extend-definitions|-e] [--no-command-file] [--command-file|-f]
                     [--interactive|-i] [--mode|-m] [--language|-l]

Builds and runs projects

required positional arguments:
  FILE            (Start) file to build and execute

optional named arguments:
  --help, -h                                       ? show this help message and exit
  --run-only                                       ? Just run the application and do not build it
  --build-only                                     ? Just build the application and do not run it
  --silent, -s                                     ? No additional output - only output from executed file
  --verbose, -v                                    ? Verbose output
  --no-makefile                                    ? Do not use the Makefile if it exists
  --makefile MAKEFILE                              ? Specify and use given alternative makefile instead of
                                                       predefinitions
  --replace-definitions, -r REPLACE-DEFINITIONS    ? Replace predefinitions with rules from given file
  --extend-definitions, -e EXTEND-DEFINITIONS      ? Extend predefinitions with rules from given file
  --no-command-file                                ? Do not use the command file if it exists
  --command-file, -f COMMAND-FILE                  ? Specify and use given alternative command file instead of
                                                       predefinitions
  --interactive, -i                                ? Do not capture any output; allow interactive debugging
                                                       sessions
  --mode, -m MODE                                  ? Specify build mode
                                                       Choices: [debug, release], case sensitive
  --language, -l LANGUAGE                          ? Disable language auto detection and use the given one
                                                       Choices: [bash, c, cpp, d, dash, fish, haskell, ipython,
                                                       ipython2, ipython3, javascript, lua, nim, pdf, perl, php,
                                                       pure, python, python2, python3, racket, ruby, rust, scheme,
                                                       sent, sh, svg], case sensitive
```

### vim-plugin:

The vim plugin exports three commands:

* `Build`: base command
* `DBuild`: performs a debug build
* `RBuild`: performs a release build

