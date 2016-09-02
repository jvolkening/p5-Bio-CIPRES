#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => "$ENV{HOME}/.cipres",
);

my @jobs = $u->list_jobs;
for my $j (@jobs) {
    my $s = $j->stage;
    print "$j :: $s\n";
    if ($j->is_finished) {
        $j->delete;
    }
}
