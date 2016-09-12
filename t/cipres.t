#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Net::Ping;
use List::Util qw/first/;

use Bio::CIPRES;
use Bio::CIPRES::Error qw/:constants/;

# Bad credentials
my $ua = Bio::CIPRES->new(
    user   => 'foo',
    pass   => 'bar',
    app_id => 'baz',
);

ok ($ua->isa('Bio::CIPRES'), "returned Bio::CIPRES object");

SKIP: {
   
    my $p = Net::Ping->new();
    skip "CIPRES server not reachable" if (! $p->ping($Bio::CIPRES::SERVER));

    # job submission should fail with authentication error
    eval { $ua->submit_job() };
    ok ($@, "submit_job threw exception");
    ok ($@->isa('Bio::CIPRES::Error'), "returned Bio::CIPRES::Error object");
    ok ($@ == ERR_AUTHENTICATION, "exception was ERR_AUTHENTICATION");

    skip "No valid credentials available" if (! -r "$ENV{HOME}/.cipres");

    # Good (testing) credentials
    $ua = Bio::CIPRES->new(
        conf => "$ENV{HOME}/.cipres",
    );

    my $job = $ua->submit_job(
        'tool'                => 'READSEQ',
        'input.infile_'       => ">test_seq\nAATGCC",
        'vparam.runtime_'     => '0.5',
        'vparam.input_type_'  => '8',  # FASTA
        'vparam.output_type_' => '13', # RAW
    );
    ok ($job->isa('Bio::CIPRES::Job'), "returned Bio::CIPRES::Job object");

    while (! $job->is_finished) {
        sleep $job->poll_interval;
        $job->refresh_status;
    }

    ok ($job->stage eq 'COMPLETED', "returned expected job stage");

    my $result = first {$_->name eq 'outfile.txt'} $job->list_outputs;
    ok ($result->isa('Bio::CIPRES::Output'), "returned Bio::CIPRES::Output object");
    ok ($result->size == 8, "output correct size");
    ok ($result->group eq 'outputfile_plain', "output correct group");

    my $contents = $result->download;
    ok ($contents =~ /^AATGCC/, "returned expected job output");

    ok ($job->delete, "job deleted without error");
}

done_testing();
exit;
