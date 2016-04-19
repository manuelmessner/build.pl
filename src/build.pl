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


# includes: {{{
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

# utils: defined_and_true, linev, slurp {{{
sub defined_and_true($) {
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
        proc => 'build',
        description => 'Builds and runs projects',
    );
    $arg_parser->add_args([
            '--language', '-l',
            choices => [sort keys $cfg->{languages}->%*],
            help => 'Disable language auto detection and use the given one',
        ], [
            '--mode', '-m',
            choices => [qw(debug release)],
            help => 'Specify build mode'
        ], [
            '--interactive', '-i',
            type => 'Bool',
            help => 'Do not capture any output; allow interactive debugging sessions',
        ], [
            '--command-file', '-f',
            help => 'Specify and use given alternative command file instead of predefinitions',
        ], [
            '--no-command-file',
            type => 'Bool',
            help => 'Do not use the command file if it exists',
        ], [
            '--extend-definitions', '-e',
            help => 'Extend predefinitions with rules from given file',
        ], [
            '--replace-definitions', '-r',
            help => 'Replace predefinitions with rules from given file',
        ], [
            '--makefile',
            help => 'Specify and use given alternative makefile instead of predefinitions',
        ], [
            '--no-makefile',
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
            'file',
            required => 1,
            help => '(Start) file to build and execute'
        ], [
            '--build-only',
            type => 'Bool',
            help => 'Just build the application and do not run it',
        ], [
            '--run-only',
            type => 'Bool',
            help => 'Just run the application and do not build it',
        ]
    );

    my $args = $arg_parser->parse_args;

    $cfg->{default}->{mode} = $args->mode if defined $args->mode;
    $cfg->{default}->{verbose} = 'true' if $args->verbose;
    $cfg->{default}->{verbose} = 'false' if $args->silent;
    $cfg->{default}->{command_file} = $args->command_file
            if defined $args->command_file;
    $cfg->{default}->{command_file} = '' if $args->no_command_file;
    $cfg->{default}->{makefile} = $args->makefile if defined $args->makefile;
    $cfg->{default}->{makefile} = '' if $args->no_makefile;
    $cfg->{default}->{extend} = $args->extend_definitions
            if defined $args->extend_definitions;
    $cfg->{default}->{replace} = $args->replace_definitions
            if defined $args->replace_definitions;
    $cfg->{default}->{buildonly} = 'true' if $args->build_only;
    $cfg->{default}->{buildonly} = 'false' if $args->run_only;
    $cfg->{default}->{runonly} = 'true' if $args->run_only;
    $cfg->{default}->{runonly} = 'false' if $args->build_only;

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
    my $ext = (fileparse $fpath, qr/\..*?$/)[2];
    return undef if not $ext;

    my $type = substr $ext, 1;
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

# includes: get_includes {{{
sub get_includes($$$) {
    my ($cfg, $filetype, $fpath) = @_;
    my @files = qx($cfg->{default}->{inc_cmd} "$filetype" "$fpath");
    chomp @files;
    return @files;
}
# }}}

# execute: execute, get_system_cmd {{{
sub get_system_cmd($$$$@) {
    my ($cfg, $tpl, $lang, $rules, @files) = @_;
    $tpl =~ s/\$METHOD/$lang->{method}/g;

    $tpl =~ s/\$METHOD/$lang->{method}/g;
    $tpl =~ s/\$FLAGS/$rules->{flags}->@*/g;
    $tpl =~ s/\$OUTFILE/"$cfg->{default}->{outfile}"/g;
    $tpl =~ s/\$FILES/@files/g;

    my @tmp = shellwords $tpl;
    return {
        cmd => shift @tmp,
        args => [@tmp],
    };
}

sub execute($$$) {
    my ($cfg, $cmd, $msg, $stdout, $stderr) = @_;
    if ($cfg->{default}->{verbose} eq 'true') {
        logi sprintf('%-9s', ucfirst $msg . ':'),
             $cmd->{cmd},
             $cmd->{args}->@*;
    }

    capture sub {
        system $cmd->{cmd}, $cmd->{args}->@*;
    } => \$stdout, \$stderr;
    chomp $stdout, chomp $stderr;

    my $line = "\033[0m${\linev 1}";
    $stdout =~ s/^/$line /gm, logs "Stdout:\n$stdout" if $stdout;
    $stderr =~ s/^/$line /gm, logw "Stderr:\n$stderr" if $stderr;

    return $? >> 8;
}
# }}}

# main: main {{{
sub main($) {
    my $cfg = Load(scalar slurp shift);

    # merge extend and replace file
    if (-e $cfg->{default}->{extend}) {
        if ($cfg->{default}->{verbose} eq 'true') {
            logi 'Ext-File: found';
        }
        merge_hashes $cfg, Load(scalar slurp $cfg->{default}->{extend});
    } elsif (-e $cfg->{default}->{replace}) {
        if ($cfg->{default}->{verbose} eq 'true') {
            logi 'Rep-File: found';
        }
        my $tmp = Load(scalar slurp $cfg->{default}->{replace});
        merge_hashes $cfg, $tmp, 'replace';
    }

    my $args = parse_args $cfg;

    # run command_file or makefile instead of normal build process
    if (-e $cfg->{default}->{command_file}) {
        my $tmp = {cmd => "./$cfg->{default}->{command_file}", args => []};
        return execute $cfg, $tmp, 'Cmd-File';
    } elsif (-e $cfg->{default}->{makefile}) {
        my $tmp = {cmd => 'make', args => []};
        return execute $cfg, $tmp, 'Makefile';
    }

    # start normal build process
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

    if ($cfg->{default}->{verbose} eq 'true') {
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
    my $rules = exists $lang->{method} ? $lang->{$lang->{method}} : $lang;


    my @ops = qw(build run);
    @ops = 'build' if defined_and_true $cfg->{default}->{buildonly};
    @ops = 'run' if defined_and_true $cfg->{default}->{runonly};

    @ops = qw(build run);
    defined_and_true $cfg->{default}->{$_.'only'} and @ops = $_, last for @ops;

    for (@ops) {
        next unless exists $rules->{$_};

        # check if $rules->{$_} is a command or a hash containing commands
        my $tpl = !ref $rules->{$_} ? $rules->{$_} : $rules->{$_}->{$mode};
        my $cmd = get_system_cmd $cfg, $tpl, $lang, $rules, $args->file;

        if ($_ eq 'build'
                and defined_and_true $rules->{includes}
                and $cfg->{default}->{inc_cmd}) {
            push $cmd->{args}->@*, get_includes $cfg, $filetype, $args->file;
        }

        my $ret = execute $cfg, $cmd, "Command";
        ($ret == 0 ? \&logs : \&loge)->('Return:   ' . $ret);
        return $ret if $_ eq 'run' or $_ eq 'build' and $ret != 0;
    }
}
# }}}

my $cfg_file;
-r $_ and $cfg_file = $_ and last for (
    "$ENV{HOME}/.config/build/config.yml",
    "$ENV{HOME}/.config/build/config.yaml",
    "$ENV{HOME}/.buildrc",
    '/etc/build.yml',
    '/etc/build.yaml',
);

exit main $cfg_file;
