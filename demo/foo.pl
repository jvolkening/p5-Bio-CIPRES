#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => '.cipres',
);

my @jobs = $u->list_jobs;
print "$_\n" for (@jobs);
