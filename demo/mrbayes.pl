#!/usr/bin/perl

use strict;
use warnings;

use Bio::CIPRES;

my $fn_in   = $ARGV[0];
my $dir_out = $ARGV[1];

my $u = Bio::CIPRES->new(
    conf => "$ENV{HOME}/.cipres",
);

my $r = sprintf("mrbayes_%05d", rand(100000));

my $tool = 'MRBAYES_XSEDE';

my $job = $u->submit_job(
    'tool'                    => $tool,
    'input.infile_'           => [$fn_in],
    'vparam.runtime_'         => 0.5,
    'vparam.mrbayesblockquery_' => 1,
    'vparam.nruns_specified_'   => 2,
    'vparam.nchains_specified_' => 4,
    'metadata.clientJobId'    => $r,
    'metadata.clientJobName'  => "job $r",
    'metadata.clientToolName' => "FOO $tool",
    'metadata.statusEmail'    => 'false',
);

print 'STATUS: ', $job->stage, "\n";

$job->wait(1800) or die "Timeout waiting for job";

my $exit_code = $job->exit_code;

if ($exit_code == 0) {
   
    for my $file ( $job->outputs(group => 'ALL_FILES') ) {
        my $out = "$dir_out/" . $file->name;
        print "S: $out\n";
        $file->download(out => $out);
    }

}
else {
    print "ERR: $exit_code\n";
    print "STDOUT:\n", $job->stdout, "\n";
    print "STDERR:\n", $job->stderr, "\n";
}

$job->delete;

exit;
