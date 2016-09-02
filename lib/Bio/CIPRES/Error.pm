package Bio::CIPRES::Error;

use 5.012;
use strict;
use warnings;

use overload
    'bool' => sub {return 0},
    '""'   => \&stringify;

use Carp;
use XML::LibXML;
use Data::Dumper;

our $VERSION = 0.001;

sub new {

    my ($class, $xml) = @_;

    my $self = bless {}, $class;

    my $dom = XML::LibXML->load_xml('string' => $xml)
        or croak "Error parsing error XML: $!";
    $self->_parse_dom( $dom );

    return $self;


}

sub stringify {

    my ($self) = @_;

    my $msg = $self->{display};
    for (@{ $self->{param_errors} }) {
        $msg .= " : Error in param \"$_->{param}\" ($_->{error})";
    }
    $msg .= "\n";

    return $msg;

}

sub _parse_dom {

    my ($self, $dom) = @_;

    # remove outer tag if necessary
    my $c = $dom->firstChild;
    $dom = $c if ($c->nodeName eq 'error');

    $self->{display} = $dom->findvalue('displayMessage');
    $self->{message} = $dom->findvalue('message');
    $self->{code}    = $dom->findvalue('code');

    # check for missing values
    map {length $self->{$_} || croak "Missing value for $_\n"} keys %$self;

    # parse messages
    for my $err ($dom->findnodes('paramError')) {
        my $ref = {
            param => $err->findvalue('param'),
            error => $err->findvalue('error'),
        };

        # check for missing values
        map {length $ref->{$_} || croak "Missing value for $_\n"} keys %$ref;

        push @{ $self->{param_errors} }, $ref;

    }

    return;

}

1;
