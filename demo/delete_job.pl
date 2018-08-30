#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => "$ENV{HOME}/.cipres",
);

my $job = $u->get_job($ARGV[0])
    or die "Error fetching job: $@\n";
$job->delete
    or die "Error deleting job: $@\n";
