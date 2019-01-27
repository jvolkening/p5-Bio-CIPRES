#!/usr/bin/perl

use strict;
use warnings;
use 5.012;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => $ARGV[0] // "$ENV{HOME}/.cipres",
);

my @jobs = $u->list_jobs;
@jobs = sort {$a->submit_time <=> $b->submit_time} @jobs;
for my $j (@jobs) {
    my $t = $j->submit_time; 
    my $s = $j->{url_results};
    my $i = $j->stage;
    say join "\t",
        $j,
        $t,
        $i,
        $s,
    ;
}
