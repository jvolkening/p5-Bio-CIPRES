#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => $ARGV[2] // "$ENV{HOME}/.cipres",
);

my $job = $u->get_job($ARGV[0]);

print 'STATUS: ', $job->stage, "\n";

$job->wait(6000) or die "Wait timeout";

my $exit_code = $job->exit_code;
if (! defined $exit_code || $exit_code == 0) {
   
    open my $se, '>', "$ARGV[1]/STDERR_FOO";
    print {$se} $job->stderr;
    close $se;

    open my $so, '>', "$ARGV[1]/STDOUT_FOO";
    print {$so} $job->stdout;
    close $so;

    my @saved;
    for ($job->outputs) {
        my $out = "$ARGV[1]/" . $_->name;
        push @saved, $out;
        $_->download(out => $out);
    }
    print "S: $_\n" for (@saved);

}
