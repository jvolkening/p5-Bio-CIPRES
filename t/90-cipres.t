#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Net::Ping;
use List::Util qw/first/;
use LWP::Simple;

use Bio::CIPRES;
use Bio::CIPRES::Error qw/:constants/;

# The first SKIP block contains limited tests which can be run without valid
# credentials. Mostly this checks that the server connection can be initiated
# and that the expected Error objects are returned on failure;

SKIP: {
   
    my $p = Net::Ping->new();

    # Check for necessary network connections and skip otherwise
    skip "CIPRES server not reachable", 7 if (! $p->ping($Bio::CIPRES::SERVER));
    skip "CIPRES httpd not reachable", 7
        if (! is_success(getprint("https://$Bio::CIPRES::SERVER")));

    # direct config with bogus credentials
    my $ua = Bio::CIPRES->new(
        user   => 'foo',
        pass   => 'bar',
        app_id => 'baz',
    );

    isa_ok( $ua, 'Bio::CIPRES' );
    ok( $ua->{cfg}->{user} eq 'foo' );

    # config from file with bogus credentials
    $ua = Bio::CIPRES->new(
        conf => 't/test_data/cipres.conf',
    );

    isa_ok( $ua, 'Bio::CIPRES' );
    ok( $ua->{cfg}->{user} eq 'bar' );

    # job submission should fail with authentication error
    eval { $ua->submit_job() };
    ok( $@, "submit_job threw expected exception" );
    #diag( "NET: $@ $!\n" );
    isa_ok( $@, 'Bio::CIPRES::Error' );
    cmp_ok( $@,  '==', ERR_AUTHENTICATION, "exception == ERR_AUTHENTICATION");

}

# The second SKIP block contains more substantial tests that will run in a
# real config file is found. These will usually only be run on the developer's
# system.

SKIP: {

    # Skip the rest if no user credentials found
    skip "No valid credentials available", 21
        if ( ! -r "$ENV{HOME}/.cipres"
        && (! defined $ENV{CIPRES_USER} || ! defined $ENV{CIPRES_PASS}) );

    # additional tests for Bio::CIPRES::Error
    eval { Bio::CIPRES::Error->new() };
    ok($@ =~ /Undefined XML string in constructor/, "new Error missing XML" );
    eval { Bio::CIPRES::Error->new('foo') };
    ok($@ =~ /Start tag expected/, "new Error invalid XML" );

    # Good (testing) credentials
    my $ua = -r "$ENV{HOME}/.cipres"
      ? Bio::CIPRES->new(
            conf => "$ENV{HOME}/.cipres",
        )
      : Bio::CIPRES->new(
            user => $ENV{CIPRES_USER},
            pass => $ENV{CIPRES_PASS},
        );
    isa_ok( $ua, 'Bio::CIPRES' );

    # try to fetch non-existant job
    eval { $ua->get_job('foobar') };
    ok( $@, "get_job() threw expected exception" );
    isa_ok( $@, 'Bio::CIPRES::Error' );
    cmp_ok( $@,  '==', ERR_NOT_FOUND, "exception == ERR_NOT_FOUND");
    cmp_ok( "$@",  'eq', "Job not found.\n", "exception eq 'Job not found'");

    # submit bad job
    eval {
        my $job = $ua->submit_job(
            'tool'                => 'CLUSTALW',
            'input.infile_'       => ">test_seq_1\nAATGCC\n>test_seq_2\nAAATGCG\n",
            'vparam.runtime_'     => '0.5',
            'bad_param_foo'       => 'bar',
        );
    };
    ok( $@, "submit_job() threw expected exception" );
    isa_ok( $@, 'Bio::CIPRES::Error' );
    cmp_ok( $@,  '==', ERR_FORM_VALIDATION, "exception == ERR_FORM_VALIDATION");
    ok( "$@" =~ /Error in param/, "exception stringification worked");

    # submit good job
    my $job = $ua->submit_job(
        'tool'                => 'CLUSTALW',
        'input.infile_'       => ">test_seq_1\nAATGCC\n>test_seq_2\nAAATGCG\n",
        'vparam.runtime_'     => '0.5',
    );
    isa_ok( $job, 'Bio::CIPRES::Job' );

    # test get_job() as well as auto-stringification by fetching same job
    $job = $ua->get_job("$job");
    isa_ok( $job, 'Bio::CIPRES::Job' );

    # test list_jobs() by finding same job
    my @jobs = $ua->list_jobs();
    $job = first { "$_" eq "$job" } @jobs;
    isa_ok( $job, 'Bio::CIPRES::Job' );

    isa_ok( $job->submit_time, 'Time::Piece' );
   
    # wait for completion and check final status/results
    ok( $job->wait(1200), "wait() returned true" );
    is( $job->stage, 'COMPLETED', "returned expected job stage" );
    cmp_ok( $job->exit_code, '==', 0, "job return expected exit status" );

    ok(! $job->is_failed, "job not failed" );
    ok(! $job->timed_out, "job not timed out" );

    # test Bio::CIPRES::Message
    my $msg = $job->messages()->[-1];
    is( $msg->stage, 'COMPLETED' , "message returned expected state" );
    ok( length $msg->text, "message returned a text summary" );
    isa_ok( $msg->timestamp, 'Time::Piece' );
    ok( "$msg" =~ /^Output/, "message stringification works" );

    my ($result) = $job->outputs(name => 'infile.aln', group => 'aligfile');
    isa_ok( $result, 'Bio::CIPRES::Output' );
    cmp_ok( $result->size, '==', 114, "output correct size" );
    ok( $result->url =~ /^http/, "output has download URL" );

    # test output download to scalar
    my $contents = $result->download;
    like( $contents, qr/^test_seq_2\s+AAAT/mi, "returned expected job output" );

    # test handling of output paths
    eval {my $res = $result->download(out => '/this/path/should/not/exist') };
    ok( $@ =~ /^Unspecified error/, "Error on non-writable path" );
    open my $touch, '>', 'foo';
    eval {$result->download(out => 'foo') };
    ok( $@ =~ /^Output file exists/, "Error on existing file" );
    ok( $result->download(out => 'foo', overwrite => 1), "Overwrite");
    unlink 'foo';

    my $stdout = $job->stdout;
    my $stderr = $job->stderr;
    ok( length  $stdout, "stdout has content" );
    ok( defined $stderr, "Stderr is defined"  );

    # try to clean up
    ok( $job->delete, "job deleted without error" );

    # submit expected timeout
    $job = $ua->submit_job(
        'tool'                => 'MAFFT_XSEDE',
        'input.infile_'       => ["t/test_data/timeout.fa"],
        'vparam.runtime_'     => '0.1',
        'vparam.analysis_type_' => 'accurate',
        'vparam.auto_analysis_' => '0',
    );
    ok( $job->wait(1200), "wait() returned true" );
    #ok( $job->timed_out(), "job timed out" );
    $job->delete;

}

done_testing();
exit;
