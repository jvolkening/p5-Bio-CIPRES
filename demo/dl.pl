#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $u = Bio::CIPRES->new(
    conf => '.cipres',
);

my $job = $u->get_job_by_handle($ARGV[0]);

print 'STATUS: ', $job->stage, "\n";

while (! $job->is_finished) {
   
    sleep $job->poll_interval;
    $job->refresh_status;
    print 'STATUS: ', $job->stage, "\n";

}

my $exit_code = $job->exit_code;
warn "E: $exit_code\n";
if ($exit_code == 0) {
   
    my $e = $job->stderr;
    print "STDERR:\n$e\n";
    my $o = $job->stdout;
    print "STDOUT:\n$o\n";
    my @saved = $job->download(group => 'aligfile', dir => '/home/jeremy/Downloads');
    print "S: $_\n" for (@saved);

}
