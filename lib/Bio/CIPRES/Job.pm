package Bio::CIPRES::Job;

use 5.012;
use strict;
use warnings;

use overload
    '""' => sub {return $_[0]->{status}->{handle}};

use Carp;
use DateTime::Format::RFC3339;
use XML::LibXML;
use Scalar::Util qw/blessed weaken/;

use Bio::CIPRES::Output;

our $VERSION = 0.001;

sub new {

    my ($class, %args) = @_;

    my $self = bless {}, $class;

    croak "Must define job parent" if (! defined $args{parent});
    croak "Parent must be a Bio::CIPRES object"
        if ( blessed($args{parent}) ne 'Bio::CIPRES' );
    $self->{parent} = $args{parent};
    weaken( $self->{parent} );

    croak "Must define initial status" if (! defined $args{dom});
    $self->_parse_status( $args{dom} );

    return $self;


}

sub delete {

    my ($self) = @_;

    return $self->{parent}->_delete( $self->{status}->{url_status} );

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

    my @sorted = sort {
        DateTime::Format::RFC3339->parse_datetime( $a->{timestamp} )
        <=>
        DateTime::Format::RFC3339->parse_datetime( $b->{timestamp} )
    } @{ $self->{status}->{messages} };

    return $sorted[-1]->{stage};

}

sub refresh_status {

    my ($self) = @_;

    my $u = $self->{parent};
    my $xml = $u->_get( $self->{status}->{url_status} );
    my $dom = XML::LibXML->load_xml( string => $xml );

    $self->_parse_status($dom);

}

sub list_output {

    my ($self) = @_;

    my $u = $self->{parent};
    my $xml = $u->_get( $self->{status}->{url_results} );
    my $dom = XML::LibXML->load_xml( string => $xml );

    return map {
        Bio::CIPRES::Output->new( dom => $_ )
    } $dom->findnodes('/results/jobfiles/jobfile');

}


sub download {

    my ($self, %args) = @_;

    my @results = $self->list_output;
    my @saved = ();

    for (@results) {
        next if ( defined $args{group} && $_->{group} ne $args{group} );
        next if ( defined $args{name } && $_->{filename}  ne $args{filename}  );
        my $outfile = $_->{filename};
        $outfile = "$args{dir}/$outfile" if (defined $args{dir});
        warn "saving $_->{url_download} to $outfile\n";
        my $res = $self->{parent}->_download(
            $_->{url_download},
            $outfile,
        );
        push @saved, $_->{filename};
    }

    return @saved;
       
}

sub exit_code {

    my ($self) = @_;

    my @results = $self->list_output;
    for (@results) {
        next if ($_->{filename} ne 'done.txt');
        my $content = $self->{parent}->_get(
            $_->{url_download}
        );
        if ($content =~ /^retval=(\d+)$/m) {
            return $1;
        }
    }
    return undef;
       
}

sub stdout {

    my ($self) = @_;

    my @results = $self->list_output;
    for (@results) {
        next if ($_->{filename} ne 'STDOUT');
        return $self->{parent}->_get(
            $_->{url_download}
        );
    }
    return undef;
       
}

sub stderr {

    my ($self) = @_;

    my @results = $self->list_output;
    for (@results) {
        next if ($_->{filename} ne 'STDERR');
        return $self->{parent}->_get(
            $_->{url_download}
        );
    }
    return undef;
       
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
        my $ref = {
            timestamp => $msg->findvalue('timestamp'),
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

Bio::CIPRES::Job - A class reprsenting a single CIPRES job

=head1 SYNOPSIS

    use Bio::CIPRES;

    my $ua = Bio::CIPRES->new(%args);

    my $job = $ua->submit

=head1 DESCRIPTION

C<Bio::CIPRES::Error> is a simple error class for the CIPRES API. It's purpose
is to parse the XML error report returned by CIPRES and provide an object that
can be used in different contexts. In boolean contexts it always returns a
false value, in string context it returns a textual summary of the error, and
in numeric context it returns the error code.

This class does not contain any methods (including the constructor) intended
to be called by the end user. It's functionality is encoded in it's overload
behavior is described above.

=head1 METHODS

None

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


