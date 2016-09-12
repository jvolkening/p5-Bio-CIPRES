package Bio::CIPRES::Job 0.001;

use 5.012;
use strict;
use warnings;

use overload
    '""' => sub {return $_[0]->{status}->{handle}};

use Carp;
use Time::Piece;
use XML::LibXML;
use Scalar::Util qw/blessed weaken/;
use List::Util qw/first/;

use Bio::CIPRES::Output;
use Bio::CIPRES::Error;


sub new {

    my ($class, %args) = @_;

    my $self = bless {}, $class;

    croak "Must define user agent" if (! defined $args{agent});
    croak "Agent must be an LWP::UserAgent object"
        if ( blessed($args{agent}) ne 'LWP::UserAgent' );
    $self->{agent} = $args{agent};
    weaken( $self->{agent} );

    croak "Must define initial status" if (! defined $args{dom});
    $self->_parse_status( $args{dom} );

    return $self;


}

sub delete {

    my ($self) = @_;

    my $res = $self->{agent}->delete( $self->{status}->{url_status} )
        or croak "LWP internal error: $@";

    die Bio::CIPRES::Error->new( $res->content )
        if (! $res->is_success);

    return 1;

}

sub is_finished {

    my ($self) = @_;

    return $self->{status}->{is_terminal} =~ /^true$/i ? 1 : 0;

}

sub poll_interval {

    my ($self) = @_;

    return $self->{status}->{delay};

}

sub stage {

    my ($self) = @_;

    # The docs say:
    #
    # "Unfortunately, the current version of CIPRES sets
    # jobstatus.jobStage in a way that's somewhat inconsistent and difficult
    # to explain. You're better off using jobstatus.messages to monitor the
    # progress of a job."
    #
    # so we follow their advice.

    map {$_->{timestamp} =~ s/(\d\d)\:(\d\d)$/$1$2/}
        @{ $self->{status}->{messages} };

    my @sorted = sort {
        $a->{timestamp} <=> $b->{timestamp}
    } @{ $self->{status}->{messages} };

    return $sorted[-1]->{stage};

}

sub refresh_status {

    my ($self) = @_;

    my $xml = $self->_get( $self->{status}->{url_status} );
    my $dom = XML::LibXML->load_xml( string => $xml );

    $self->_parse_status($dom);

}

sub _get {

    my ($self, $url) = @_;

    my $res = $self->{agent}->get( $url )
        or croak "LWP internal error: $@";

    die Bio::CIPRES::Error->new( $res->content )
        if (! $res->is_success);

    return $res->content;

}

sub list_outputs {

    my ($self) = @_;

    my $xml = $self->_get( $self->{status}->{url_results} );
    my $dom = XML::LibXML->load_xml( string => $xml );

    return map {
        Bio::CIPRES::Output->new(
            agent => $self->{agent},
            dom   => $_,
        )
    } $dom->findnodes('/results/jobfiles/jobfile');

}


sub download {

    my ($self, %args) = @_;

    my @results = $self->list_outputs;
    my @saved = ();

    for my $file (@results) {
        next if ( defined $args{group} && $file->group ne $args{group} );
        next if ( defined $args{name } && $file->name  ne $args{filename}  );
        my $outfile = $file->name;
        $outfile = "$args{dir}/$outfile" if (defined $args{dir});
        warn "saving " . $file->url . " to $outfile\n";
        my $res = $file->download(
            out => $outfile,
        );
        push @saved, $file->name;
    }

    return @saved;
    
}

sub exit_code {

    my ($self) = @_;

    my $file = first {$_->name eq 'done.txt'} $self->list_outputs;

    return undef if (! defined $file);

    my $content = $file->download;
    if ($content =~ /^retval=(\d+)$/m) {
        return $1;
    }
    
    return undef;
       
}

sub stdout {

    my ($self) = @_;

    my $file = first {$_->name eq 'STDOUT'} $self->list_outputs;

    return undef if (! defined $file);
    return $file->download;
    
}

sub stderr {

    my ($self) = @_;

    my $file = first {$_->name eq 'STDERR'} $self->list_outputs;

    return undef if (! defined $file);
    return $file->download;
    
}

sub _parse_status {

    my ($self, $dom) = @_;

    my $s   = {};

    # remove outer tag if necessary
    my $c = $dom->firstChild;
    $dom = $c if ($c->nodeName eq 'jobstatus');

    $s->{handle}      = $dom->findvalue('jobHandle');
    $s->{url_status}  = $dom->findvalue('selfUri/url');
    $s->{url_results} = $dom->findvalue('resultsUri/url');
    $s->{url_working} = $dom->findvalue('workingDirUri/url');
    $s->{delay}       = $dom->findvalue('minPollIntervalSeconds');
    $s->{is_terminal} = $dom->findvalue('terminalStage');
    $s->{is_failed}   = $dom->findvalue('failed');
    $s->{stage}       = $dom->findvalue('jobStage');
    $s->{submitted}   = $dom->findvalue('dateSubmitted');

    # check for missing values
    map {length $s->{$_} || croak "Missing value for $_\n"} keys %$s;

    # parse messages
    for my $msg ($dom->findnodes('messages/message')) {
        my $t = $msg->findvalue('timestamp');
        $t =~ s/(\d\d):(\d\d)$/$1$2/;
        my $ref = {
            timestamp => Time::Piece->strptime($t, "%Y-%m-%dT%H:%M:%S%z"),
            stage     => $msg->findvalue('stage'),
            text      => $msg->findvalue('text'),
        };

        # check for missing values
        map {length $ref->{$_} || croak "Missing value for $_\n"} keys %$ref;

        push @{ $s->{messages} }, $ref;

    }

    # parse metadata
    for my $meta ($dom->findnodes('metadata/entry')) {
        my $key = $meta->findvalue('key');
        my $val = $meta->findvalue('value');

        # check for missing values
        map {length $_ || croak "Unexpected metadata format\n"} ($key, $val);

        $s->{meta}->{$key} = $val;
    }

    $self->{status} = $s;

    return;

}

1;

__END__

=head1 NAME

Bio::CIPRES::Job - a CIPRES job

=head1 SYNOPSIS

    use Bio::CIPRES;

    my $ua  = Bio::CIPRES->new( %args );
    my $job = $ua->submit( %params );

=head1 DESCRIPTION

C<Bio::CIPRES::Job> is a class representing a single CIPRES job. It's purpose
is to simplify handling of job status and job outputs.

Users should not create C<Bio::CIPRES::Job> objects directly - they are
returned by methods in the L<Bio::CIPRES> class.

=head1 METHODS

=over 4

=item B<delete>

    $job->delete;

Deletes a job from the user workspace, including all of the output files.
Generally this should be called once a job is completed and all desired output
files have been fetched. This will help to keep the user workspace clean.

=item B<is_finished>

    if ($job->is_finished) {}

Returns true if the job has completed, false otherwise.

=item B<poll_interval>

    my $s = $job->poll_interval;

Returns the minimum number of seconds that the client should wait between
status updates. Generally this is called as part of a while loop.

=item B<stage>

    if ($job->stage eq 'COMPLETED') {}

Returns a string describing the current stage of the job.

=item B<refresh_status>

    $job->refresh_status;

Makes a call to the API to retrieve the current status of the job, and updates
the object attributes accordingly. Generally this is called as part of a while
loop while waiting for a job to complete.

=item B<list_outputs>

    for my $output ($job->list_outputs) {}

Returns an array of L<Bio::CIPRES::Output> objects representing files
generated by the job. Generally this should only be called after a job has
completed.

=item B<exit_code>

Returns the actual exit code of the job on the remote server. Exit codes < 0
indicate API or server errors, while exit codes > 0 indicate errors in the job
tool itself (possibly described in the tool's documentation).

=item B<stdout>

Returns the STDOUT from the job as a string.

=item B<stderr>

Returns the STDERR from the job as a string.

=item B<download>

Currently deprecated and undocumented (use L<Bio::CIPRES::Output::download>
instead).

=back

=head1 CAVEATS AND BUGS

This is code is in alpha testing stage and the API is not guaranteed to be
stable.

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jdv@base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Jeremy Volkening

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=cut


