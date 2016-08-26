#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => '.cipres',
);

my $r = sprintf("run%05d", rand(100000));

my $tool = 'CLUSTALW';

my $job = $u->submit_job(
    'tool'                    => $tool,
    'input.infile_'           => [$ARGV[0]],
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
if ($exit_code == 0) {
   
    my $e = $job->stderr;
    my $o = $job->stdout;
    @saved = $job->download(group => 'aligfile');
    print "S: $_\n" for (@saved);

}
