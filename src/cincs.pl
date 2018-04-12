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


use strict;
use utf8;
use warnings;
use feature qw(state say);

use Cwd qw(realpath);
use File::Basename;


my $g_cfg = {
    c => {
        mark  => '^\s*#\s*include\s*"\s*(.*?)\s*"\s*$',
        subst => sub {
            local $_ = shift // $_;
            s/\.h$/.c/;
            return $_;
        },
    },
    cpp => {
        mark  => '^\s*#\s*include\s*"(.*?)\s*$"',
        subst => sub {
            local $_ = shift // $_;
            s/\.h$/.cpp/;
            return $_;
        },
    },
    d => {
        mark  => '^\s*import\s+(\S+).*;.*$',
        subst => sub {
            local $_ = shift // $_;
            return undef if /^(?:std|core|etc)\./;
            s/\./\//g;
            $_ .= '.d';
            return $_;
        },
    },
    java => {
        mark => '^\s*import\s+(.*)\s*;\s*$',
        subst => [''],
    },
};


my ($g_ft, $g_fpath) = @ARGV;
die "usage: " . basename($0) . "<filetype> <file>\n" if not ($g_fpath && $g_ft);
exit 0 unless exists $g_cfg->{$g_ft};


sub uniq(@) {
    local %_;
    return grep { not $_{$_}++ } @_;
}

sub parse_inc($) {
    return shift unless $g_cfg->{$g_ft}->{subst};
    local $_ = $g_cfg->{$g_ft}->{subst}->(shift);
    return defined $_ && -e $_ ? $_ : undef;
}

sub get_includes {
    my $fpath = shift // $_;
    state %done;
    return () if exists $done{$fpath};
    $done{$fpath} = 1;

    open my $f, $fpath or die "Could not open file: $fpath: $!\n";
    my @incs = map {
        my $inc = /$g_cfg->{$g_ft}->{mark}/ ? parse_inc $1 : undef;
        my $path = defined $inc ? realpath $inc : undef;
        defined $path && $path ne $g_fpath ? $path : ();
    } <$f>;
    close $f;

    push @incs, get_includes($_) for @incs;
    return uniq @incs;
}


$g_fpath = realpath $g_fpath;
chdir dirname $g_fpath;
say for get_includes $g_fpath;
