package Bio::CIPRES::Job;

use 5.012;
use strict;
use warnings;

use overload
    '""' => sub {return $_[0]->{status}->{handle}};

use Carp;
use DateTime::Format::RFC3339;
use XML::LibXML;
use Data::Dumper;

use Bio::CIPRES::Output;

our $VERSION = 0.001;

sub new {

    my ($class, %args) = @_;

    my $self = bless {}, $class;

    croak "Must define job parent" if (! defined $args{parent});
    $self->{parent} = $args{parent};
    #TODO: check that $parent is of class BIO::CIPRES

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
        Bio::CIPRES::Output->new( parent => $self, dom => $_ )
    } $dom->findnodes('/results/jobfiles/jobfile');

}


sub download {

    my ($self, %args) = @_;

    my @results = $self->list_output;
    my @saved = ();

    for (@results) {
        next if ( defined $args{group} && $_->{group} ne $args{group} );
        next if ( defined $args{name } && $_->{name}  ne $args{name}  );
        my $outfile = $_->{name};
        $outfile = "$args{dir}/$outfile" if (defined $args{dir});
        warn "saving $_->{url_download} to $outfile\n";
        my $res = $self->{parent}->_download(
            $_->{url_download},
            $outfile,
        );
        push @saved, $_->{name};
    }

    return @saved;
       
}

sub exit_code {

    my ($self) = @_;

    my @results = $self->list_output;
    for (@results) {
        next if ($_->{name} ne 'term.txt');
        my $content = $self->{parent}->_get(
            $_->{url_download}
        );
        if ($content =~ /^ExitCode=(\d+)/m) {
            return $1;
        }
    }

    return undef;
       
}

sub stdout {

    my ($self) = @_;

    my @results = $self->list_output;
    for (@results) {
        next if ($_->{name} ne 'STDOUT');
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
        next if ($_->{name} ne 'STDERR');
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
