use Data::Dumper;
use Cwd;

use strict;
use warnings;

my @SKIP = qw(
  b6c86a021eb9373b11f0caec833b09137a88c159
  08bdc37dec9033335dcbb8fb2703e58f88db900b
  db17e44c829529949cd4d18319bef8cb327bedd8
  e4148a01da6fdf4d93082c9bc8709a53c1858ad0
  c6a64f75e03e0a21101aab4255140e3e9e071eed
  be4c31a6109390379b17ca32d6954ff6a2a2f99c
  117467892eb7e154ab1122a0598f5d2a7fdc0f7d
  6a76f2791b6ee2e2547c8a0901b91a79c61b3894
  543e11a288dd3492aaa6ae553040ffbe4361ba35
  4136c2081d7ec176238d5926d95870320820ab3e
  2b059cba6b70b229c28d318b02becd463cd0848a
  a2748fbba2cf45a739076ad319f4c0adba280653
  a8793decec1bc146760126dd65698ed3f955f687
);
my %SKIP;
foreach (@SKIP) {$SKIP{$_} = 1}

my @PRUNE = qw(
  24acc3201319541395e6fca81ef0fe3cffad1a77
  2ba869e03b5ec54b2f2c4d59e50e2619b8e3c1b6
  e702da011d7a11abcbf4121ce99b38d4b022a11b
  4c567fb965fe75c6c80be36f69514e7aa53367a3
);
my %PRUNE;
foreach (@PRUNE) {$PRUNE{$_} = 1}

my @commits;
my %commits;
open HIST, "git log scowl-7.0^..master --reverse --pretty='format:%H %P' |";
while (<HIST>) {
    chomp;
    my @d = split / /;
    my $id = shift @d;
    next if $PRUNE{$id};
    @d = grep {!$PRUNE{$_}} @d;
    my $d = {id => $id, parentsId => \@d};
    push @commits, $d;
    $commits{$id} = $d;
}
# don't care about first commits parents
$commits[0]{parentsId} = [];

$commits[0]->{w_change} = 1;
my $GIT="git log scowl-7.0^..master --pretty='format:%H' ";
my $FILTER = "-- . ':!site/' ':!.misc/' ':!**/README*' ':!README*'";
open HIST, "($GIT $FILTER && echo && $GIT --first-parent --merges $FILTER && echo) | ";
while (<HIST>) {
    chomp;
    die unless defined $commits{$_};
    $commits{$_}->{w_change} = 1;
}

#
# Read existing entires.  
# If option A and `newId` is defined is used the commit will be  assumed done.
# If option B is used and `cached` is defined the commit messages
#   will be re-done, but the contents will not be re-done.
# Only one option can be used at a time, uncommon the one you want
$/='===---===';
open HIST, "git log diff --pretty='format:~ %H ~%n%B%n===---===%n' |";
while (<HIST>) {
    next if /^\s+$/s;
    my ($new) = /~ ([a-z0-9]+) ~/ or die;
    my ($orig) = /= ([a-z0-9]+)\s+===/s or die;
    my $failed = 1 if /^BUILD FAILED./m;
    die unless defined $commits{$orig};
    $commits{$orig}->{newId} = $new; # option A
    #$commits{$orig}->{cached} = $new; # option B
    $commits{$orig}->{failed} = 1 if $failed;
    #print "$new $orig $failed\n";
}

sub sys ($) {
    my $res = system($_[0]);
    if ($res == 0) {
        return;
    } elsif ($? == -1) {
        print STDERR "failed to execute: $!\n";
        exit(2);
    } elsif ($? & 127) {
        printf STDERR "system $_[0] died with signal %d\n", ($? & 127);
        kill 'TERM', 0;
        exit(1);
    } else {
        die "system $_[0] failed: $?"
    }
}

undef $/;
foreach my $c (@commits) {
    next if defined $c->{newId};
    sys "git clean -x -d -f";
    sys "git reset --hard";
    sys "git checkout $c->{id}";
    open F, "git log -1 --pretty='format:%an%x00%ae%x00%ad%x00%B' |";
    my ($name,$email,$date,$msg) = split /\0/, <F>;
    $msg =~ s/^([^\n]+)\n?//s or die;
    my $subject = $1;
    close F;
    $ENV{GIT_AUTHOR_NAME} = $name;
    $ENV{GIT_AUTHOR_EMAIL} = $email;
    $ENV{GIT_AUTHOR_DATE} = $date;
    my $parents = '';
    foreach (@{$c->{parentsId}}) {
        my $pid = $commits{$_}{newId};
        die unless defined $pid;
        $parents .= "-p $pid ";
    }
    my $err;
    if ($c->{cached}) {
        print STDERR "Using cached copy: $@\n";
        sys "git read-tree --prefix=wordlists $c->{cached} && git checkout-index -a";
        $err = $c->{failed};
    } elsif ($c->{w_change} && !$SKIP{$c->{id}}) {
        my $dir = getcwd;
        eval {
            sys "make -C scowl l/levels-list 2> /dev/null";
            sys "make && mkdir scowl/speller/hunspell && make -C scowl/speller hunspell";
            mkdir "wordlists" or die;
            chdir "wordlists" or die;
            if (-e '../scowl/speller/hunspell/wordlist-en_US.zip') {
                sys 'for f in ../scowl/speller/hunspell/wordlist-en_*.zip; do unzip -a -n $f; done';
            } else {
                sys 'for f in ../scowl/speller/*.tocheck; do cp $f `basename $f .tocheck`.txt; done';
            }
            sys "git update-index --add en_*.txt";
        };
        $err = $@;
        chdir $dir or die;
        if ($err) {
            print STDERR "BUILD FAILED: $@\n";
            sys "rm -rf wordlists";
            my $pid = $commits{$c->{parentsId}[0]}{newId};
            sys "git read-tree --prefix=wordlists $pid && git checkout-index -a";
        }
    } else {
        my $pid = $commits{$c->{parentsId}[0]}{newId};
        sys "git read-tree --prefix=wordlists $pid && git checkout-index -a";
    }
    sys "cp ../README.md wordlists/";
    sys "git add wordlists/README.md";
    open F, ">msg.txt";
    my $tree = `git write-tree --prefix=wordlists/`;
    $tree =~ s/\s+$//;
    my $pid = $commits{$c->{parentsId}[0]}{newId};
    my $ptree = `git rev-parse $pid^{tree}` if defined $pid;
    $ptree =~ s/\s+$//;
    if (defined $ptree && $tree eq $ptree) {
        print F "($subject)\n";
    } else {
        print F "$subject\n";
    }
    print F $msg;
    if    ($SKIP{$c->{id}})                   {print F "\nBUILD SKIPPED."}
    elsif ($err)                              {print F "\nBUILD FAILED."}
    elsif (defined $ptree && $tree eq $ptree) {print F "\nNO CHANGE."}
    print F "\n= $c->{id}\n";
    open F, "cat msg.txt | git commit-tree $tree $parents |";
    my $newId = <F>;
    chop $newId;
    print STDOUT "************* $newId\n";
    print STDERR "************* $newId\n";
    sys "git branch -f diff $newId";
    $c->{newId} = $newId;
}

open TAGS, "git show-ref --tags |";

$/ = "\n";
while (<TAGS>) {
    my ($id, $tag) = m~(\S+) refs/tags/(\S+)~ or die "Bad line: $_";
    next if $tag =~ m~^diff/~;
    my $c = $commits{$id} or die;
    sys("git tag -f diff/$tag $c->{newId}");
}
