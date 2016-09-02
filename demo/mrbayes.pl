#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => "$ENV{HOME}/.cipres",
);

my $r = sprintf("mrbayes_%05d", rand(100000));

my $tool = 'MRBAYES_XSEDE';

my $job = $u->submit_job(
    'tool'                    => $tool,
    'input.infile_'           => [$ARGV[0]],
    'vparam.runtime_'         => 4,
    'vparam.mrbayesblockquery_' => 1,
    'vparam.nruns_specified_'   => 2,
    'vparam.nchains_specified_' => 4,
    'metadata.clientJobId'    => $r,
    'metadata.clientJobName'  => "job $r",
    'metadata.clientToolName' => "FOO $tool",
    'metadata.statusEmail'    => 'true',
    'metadata.emailAddress'   => 'jdv@base2bio.com',
);

print 'STATUS: ', $job->stage, "\n";

while (! $job->is_finished) {
   
    sleep $job->poll_interval;
    $job->refresh_status;
    print 'STATUS: ', $job->stage, "\n";

}

my $exit_code = $job->exit_code;
my $e = $job->stderr;
my $o = $job->stdout;
if ($exit_code == 0) {
   
    my @saved = $job->download(group => 'ALL_FILES', dir => $ARGV[1]);
    print "S: $_\n" for (@saved);

}
else {
    print "ERR!\n";
    print "STDOUT:\n$o\n";
    print "STDERR:\n$e\n";
}
