#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => $ARGV[1] // "$ENV{HOME}/.cipres",
);

my $job = $u->get_job_by_handle($ARGV[0]);

for ( $job->list_output ) {
    print join( "\t",    
        $_->name,
        $_->group,
        $_->size,
        $_->url,
    ), "\n";
}