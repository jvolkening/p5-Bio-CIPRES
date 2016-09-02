#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => "$ENV{HOME}/.cipres",
);

my @jobs = $u->list_jobs;
for my $j (@jobs) {
    my $s = $j->{status}->{url_results};
    my $i = $j->stage;
    print "$i $s\n";
}
