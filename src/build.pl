#! /usr/bin/perl


# This file is part of build.pl.
#
# build.pl is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# build.pl is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with build.pl.  If not, see <http://www.gnu.org/licenses/>.


# includes {{{
use feature qw(postderef postderef_qq say);
use strict;
use utf8;
use warnings;
no warnings qw(experimental::postderef);

use File::Basename qw(basename fileparse);
use Getopt::ArgParse;
use IO::CaptureOutput qw(capture);
use Text::ParseWords;
use YAML;
# }}}

# utils: is_true, linev, slurp {{{
sub is_true($) {
    return defined $_[0] && $_[0] eq 'true';
}

sub linev($) {
    local $_ = shift;
    return "\e(0\x78\e(B" x $_;
}

sub slurp {
    local $_ = shift // $_;
    my $trim = shift;
    return undef unless defined wantarray;

    local @_ = do {
        open my $f, '<', $_ or die "Could not open file: $_: $!\n";
        local $/ = undef unless wantarray;
        <$f>;
    };

    chomp @_ if $trim;
    return (wantarray ? @_ : shift);
}
# }}}

# arguments: parse_args {{{
sub parse_args($) {
    my ($cfg) = @_;

    my $arg_parser  = Getopt::ArgParse->new_parser(
        proc           => 'build',
        parser_configs => ["no_ignore_case"],
        help           => 'Builds and runs projects using predefined rules.',
        description    => <<END,
This application builds and runs project using a predefined ruleset.
The rules have to be defined in a configuration files, located in one of the
following places:
'\$HOME/.config/build/config.yml',
'\$HOME/.config/build/config.yaml',
'\$HOME/.config/build.yml',
'\$HOME/.config/build.yaml',
'\$HOME/.buildrc',
'/etc/build.yml',
'/etc/build.yaml'.

The return values are related to the to-be-build/to-be-executed application:
0 indicates success,
1 indicates failure and
2 indicates a signal was received.

Build offers a way to directly pass runtime arguments:

  build [option...] file [--] [rt_arg...]
  build [option...] -- -- [rt_arg...]
END
    );
    $arg_parser->add_args(
        [
            '--language', '-l',
            choices => [sort keys $cfg->{languages}->%*],
            help => 'Disable language auto detection and use the given one',
        ], [
            '--sudo',
            type => 'Bool',
            help => 'If a build rule exists, run the built application with ' .
                    'superuser privileges. Otherwise execute the given file ' .
                    'with superuser privileges.'
        ], [
            '--debug',
            type => 'Bool',
            help => 'Build in debug mode (alternative for `-m debug`)',
        ], [
            '--release',
            type => 'Bool',
            help => 'Build in release mode (alternative for `-m release`)',
        ], [
            '--mode', '-m',
            choices => [qw(d debug r release)],
            help => 'Specify build mode'
        ], [
            '--out-file', '-o',
            help => 'Specify and use an alternative output filename',
        ], [
            '--interactive', '-i',
            type => 'Bool',
            help => 'Do not capture any output; allow interactive debugging ' .
                    'sessions',
        ], [
            '--command-file', '-f',
            help => 'Specify and use given alternative command file instead ' .
                    'of predefinitions',
        ], [
            '--no-command-file',
            type => 'Bool',
            help => 'Do not use the command file if it exists',
        ], [
            '--extend-definitions', '-E',
            help => 'Extend predefinitions with rules from given file',
        ], [
            '--replace-definitions', '-R',
            help => 'Replace predefinitions with rules from given file',
        ], [
            '--makefile',
            help => 'Specify and use given alternative makefile instead of ' .
                    'predefinitions',
        ], [
            '--no-makefile', '-n',
            type => 'Bool',
            help => 'Do not use the Makefile if it exists',
        ], [
            '--verbose', '-v',
            type => 'Bool',
            help => 'Verbose output',
        ], [
            '--silent', '-s',
            type => 'Bool',
            help => 'No additional output - only output from executed file',
        ], [
            '--build-only', '-b',
            type => 'Bool',
            help => 'Just build the application and do not run it',
        ], [
            '--run-only', '-r',
            type => 'Bool',
            help => 'Just run the application and do not build it',
        ], [
            '--method', '-M',
            help => 'Specify and use given method to build/run instead of ' .
                    'predefinitions',
        ], [
            'file',
            help => 'File to build and/or execute'
        ],
    );

    my $args = $arg_parser->parse_args;
    my %modes = (
        d       => 'debug',
        r       => 'release',
        debug   => 'debug',
        release => 'release',
    );

    $cfg->{default}->{outfile} = $args->out_file if defined $args->out_file;
    $cfg->{default}->{mode} = $modes{$args->mode} if defined $args->mode;
    $cfg->{default}->{mode} = 'release' if $args->release;
    $cfg->{default}->{mode} = 'debug' if $args->debug;
    $cfg->{default}->{verbose} = 'true'  if $args->verbose;
    $cfg->{default}->{verbose} = 'false' if $args->silent;
    $cfg->{default}->{command_file} = $args->command_file
            if defined $args->command_file;
    $cfg->{default}->{command_file} = '' if $args->no_command_file;
    $cfg->{default}->{makefile} = $args->makefile if defined $args->makefile;
    $cfg->{default}->{makefile} = ''              if $args->no_makefile;
    $cfg->{default}->{extend} = $args->extend_definitions
            if defined $args->extend_definitions;
    $cfg->{default}->{replace} = $args->replace_definitions
            if defined $args->replace_definitions;
    $cfg->{default}->{buildonly}   = 'true'  if $args->build_only;
    $cfg->{default}->{buildonly}   = 'false' if $args->run_only;
    $cfg->{default}->{runonly}     = 'true'  if $args->run_only;
    $cfg->{default}->{runonly}     = 'false' if $args->build_only;
    $cfg->{default}->{interactive} = 'true'  if $args->interactive;
    $cfg->{default}->{verbose}     = 'false' if $args->interactive;
    $cfg->{default}->{sudo}        = 'true'  if $args->sudo;

    $cfg->{default}->{_method} = $args->method if defined $args->method;
    $cfg->{default}->{_args} = [$arg_parser->argv];

    return $args;
}
# }}}

# extend: merge_hashes {{{
sub merge_hashes($$;$) {
    my ($into, $from, $replace) = @_;

    for (keys %$from) {
        if ($replace or not exists $into->{$_} or not ref $into->{$_}) {
            $into->{$_} = $from->{$_};
        } elsif (ref $into->{$_} eq 'ARRAY') {
            push $into->{$_}->@*, $from->{$_}->@*;
        } else {
            &merge_hashes($into->{$_}, $from->{$_}, $replace);
        }
    }
}
# }}}

# log: loge, logi, logs, logw {{{
sub loge { say "\033[0;31mERROR:\033[0m    @_"; }
sub logi { say "\033[0mINFO:\033[0m     @_"; }
sub logs { say "\033[0;32mSUCCESS\033[0m   @_"; }
sub logw { say "\033[0;33mWARNING\033[0m   @_"; }
# }}}

# shebang: get_shebang {{{
sub get_shebang($) {
    my ($fpath) = @_;

    open my $fh, $fpath or die "Could not open file: $fpath: $!\n";
    local $_ = <$fh>;
    close $fh;
    chomp;


    return undef unless s/^#!\s*//;
    /^([\S]+)\s*(.*)$/;
    return {
        all => $_,
        cmd => $1,
        args => [shellwords $2],
    };
}
# }}}

# filetype: get_filetype {{{
sub _guess_ft_by_ext($$) {
    my ($cfg, $fpath) = @_;
    my $ext = (fileparse $fpath, qr/\.[^.]*$/)[2];
    return undef if not $ext;

    my $type = substr $ext, 1;
    return undef if not $type;

    my $langs = $cfg->{languages};
    return [grep { $langs->{$_}->{filetype} eq $type } keys %$langs] || undef;
}

sub _guess_ft_by_shebang($$$) {
    my ($cfg, $fpath, $shebang) = @_;

    my $base = basename $shebang->{cmd};
    return $base if exists $cfg->{languages}->{$base};

    exists $cfg->{languages}->{$_} and return $_ for $shebang->{args}->@*;

    return undef;
}

sub get_filetype($$$) {
    my ($cfg, $args, $shebang) = @_;

    # User has defined a language by hand. Use it!
    return $args->language if defined $args->language;

    my $types = _guess_ft_by_ext $cfg, $args->file;
    # We got exactly one result from parsing the file extension.
    return $types->[0] if defined $types and @$types == 1;

    my $type = _guess_ft_by_shebang $cfg, $args->file, $shebang;
    return $type;
}
# }}}

# includes: get_includes, get_subcmd {{{
sub get_includes($$$) {
    my ($cfg, $filetype, $fpath) = @_;
    my @files = qx($cfg->{default}->{inc_cmd} "$filetype" "$fpath");
    chomp @files;
    return @files;
}

sub get_subcmd($$) {
    my ($cfg, $tpl) = @_;

    while ($tpl =~ /(\$\((.*?)\))/) {
        logi "SubCmd:   $2" if is_true $cfg->{default}->{verbose};

        my $out = qx($2);
        chomp $out;

        $tpl =~ s/\Q$1\E/$out/g;
    }

    return $tpl;
}
# }}}

# execute: execute, get_system_cmd {{{
sub get_system_cmd($$$$@) {
    my ($cfg, $tpl, $lang, $rules, @files) = @_;

    $tpl =~ s/\$METHOD/$lang->{method}/g;
    $tpl =~ s/\$FLAGS/$rules->{flags}->@*/g;
    $tpl =~ s/\$OUTFILE/"$cfg->{default}->{outfile}"/g;
    $tpl =~ s/\$FILES/@files/g;

    $tpl = get_subcmd($cfg, $tpl);

    my @tmp = shellwords $tpl;

    return {
        cmd  => shift @tmp,
        args => [@tmp],
        sudo => is_true $cfg->{default}->{sudo},
    }
}

sub execute($$$;$) {
    my ($cfg, $cmd, $msg, $no_args) = @_;
    my ($stdout, $stderr);
    my (@cases, $ret, $sig);

    push $cmd->{args}->@*, $cfg->{default}->{_args}->@* unless $no_args;

    if ($cmd->{sudo}) {
        unshift $cmd->{args}->@*, $cmd->{cmd};
        $cmd->{cmd} = '/usr/bin/sudo';
    }

    if (is_true $cfg->{default}->{verbose}) {
        logi sprintf('%-9s', ucfirst $msg . ':'),
            $cmd->{cmd},
            $cmd->{args}->@*;
    }

    if ($cfg->{default}->{interactive}) {
        system $cmd->{cmd}, $cmd->{args}->@*;
        goto out;
    }

    capture sub {
        system $cmd->{cmd}, $cmd->{args}->@*;
    } => \$stdout, \$stderr;
    chomp $stdout, chomp $stderr;

    if (is_true $cfg->{default}->{verbose}) {
        my $line = "\033[0m${\linev 1}";
        $stdout =~ s/^/$line /gm, logs "Stdout:\n$stdout" if $stdout;
        $stderr =~ s/^/$line /gm, logw "Stderr:\n$stderr" if $stderr;
    } else {
        say $stdout if $stdout;
        say $stderr if $stderr;
    }

out:
    $sig = $? & 127;
    $ret = $? >> 8;

    @cases = $sig ? (\&loge, 'Signal:   ' . $sig, 2) :
             $ret ? (\&loge, 'Return:   ' . $ret, 1) :
                    (\&logs, 'Return:   ' . $ret, 0);
    $cases[0]->($cases[1]) unless is_true $cfg->{default}->{interactive};

    return $cases[2];
}
# }}}

# main: main {{{
sub main($) {
    my $cfg = Load(scalar slurp shift);
    my $args = parse_args $cfg;

    # merge extend and replace file
    if (-e $cfg->{default}->{extend}) {
        if (is_true $cfg->{default}->{verbose}) {
            logi 'Ext-File: found';
        }
        merge_hashes $cfg, Load(scalar slurp $cfg->{default}->{extend});
    } elsif (-e $cfg->{default}->{replace}) {
        if (is_true $cfg->{default}->{verbose}) {
            logi 'Rep-File: found';
        }
        my $tmp = Load(scalar slurp $cfg->{default}->{replace});
        merge_hashes $cfg, $tmp, 'replace';
    }

    # run command_file or makefile instead of normal build process
    if (-e $cfg->{default}->{command_file}) {
        my $cmd = get_system_cmd $cfg, "./$cfg->{default}->{command_file}", '', '';
        return execute $cfg, $cmd, 'Cmd-File';
    } elsif (-e $cfg->{default}->{makefile}) {
        my $cmd = get_system_cmd $cfg, '/usr/bin/make', '', '';
        return execute $cfg, $cmd, 'Makefile';
    }

    # start normal build process
    unless (defined $args->file) {
        loge 'No file to build/execute defined!';
        return 1;
    }

    unless (-e $args->file) {
        loge 'Could not find file to execute!';
        return 1;
    }

    my $shebang = get_shebang $args->file;
    my $filetype = get_filetype $cfg, $args, $shebang;
    unless (defined $filetype) {
        loge 'Could not determine filetype!';
        return 1;
    }

    if (is_true $cfg->{default}->{verbose}) {
        logi 'Filename: ' . $args->file;
        logi 'Filetype: ' . $filetype;
        logi 'Mode:     ' . $cfg->{default}->{mode};
    }

    my $priority = shift $cfg->{default}->{priority}->@*;
    if (defined $priority and $priority eq 'shebang' and defined $shebang) {
        push $shebang->{args}->@*, $args->file;
        return execute $cfg, $shebang, 'shebang';
    }

    # priority is not defined or priority equals rules or shebang is not defined
    my $lang = $cfg->{languages}->{$filetype};
    my $mode = $cfg->{default}->{mode};

    # a method was defined, check if rules for that method exist; if so use them
    if (exists $cfg->{default}->{_method} and
        exists $lang->{$cfg->{default}->{_method}}) {
        $lang->{method} = $cfg->{default}->{_method};
    }

    my $rules = exists $lang->{method} ? $lang->{$lang->{method}} : $lang;


    my @ops = qw(build run);
    is_true $cfg->{default}->{$_.'only'} and @ops = $_, last for @ops;

    my $ret = 0;
    for (@ops) {
        next unless exists $rules->{$_};

        if (is_true $cfg->{default}->{verbose}) {
            logi 'Action:   ' . $_;
        }

        # check if $rules->{$_} is a command or a hash containing commands
        my $tpl = !ref $rules->{$_} ? $rules->{$_} : $rules->{$_}->{$mode};
        my $cmd = get_system_cmd $cfg, $tpl, $lang, $rules, $args->file;

        if ($_ eq 'build') {
            # never build with superuser privileges!
            $cmd->{sudo} = 0;

            if (is_true $rules->{includes} and $cfg->{default}->{inc_cmd}) {
                push $cmd->{args}->@*, get_includes $cfg, $filetype, $args->file;
            }
        }

        $ret = execute $cfg, $cmd, "Command", $_ eq 'build';
        last if $ret != 0;
        # return $ret if $_ eq 'run' or $_ eq 'build' and $ret != 0;
    }
    return $ret;
}

# }}}

my $cfg_file;
-r $_ and $cfg_file = $_ and last for (
    "$ENV{HOME}/.config/build/config.yml",
    "$ENV{HOME}/.config/build/config.yaml",
    "$ENV{HOME}/.config/build.yml",
    "$ENV{HOME}/.config/build.yaml",
    "$ENV{HOME}/.buildrc",
    '/etc/build.yml',
    '/etc/build.yaml',
);

unless (defined $cfg_file) {
    loge "Could not find configuration file!";
    exit 1;
}

exit main $cfg_file;
