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
        'tool'                => 'CLUSTALW',
        'input.infile_'       => ">test_seq_1\nAATGCC\n>test_seq_2\nAAATGCG\n",
        'vparam.runtime_'     => '0.5',
    );
    ok ($job->isa('Bio::CIPRES::Job'), "returned Bio::CIPRES::Job object");
    
    ok ($job->wait(600), "wait() returned true");

    ok ($job->stage eq 'COMPLETED', "returned expected job stage");

    ok ($job->exit_code == 0, "job return expected exit status");

    my ($result) = $job->outputs(name => 'infile.aln', group => 'aligfile');
    ok ($result->isa('Bio::CIPRES::Output'), "returned Bio::CIPRES::Output object");
    ok ($result->size == 119, "output correct size");

    my $contents = $result->download;
    ok ($contents =~ /^test_seq_2\s+AAAT/mi, "returned expected job output");

    ok ($job->delete, "job deleted without error");
}

done_testing();
exit;
