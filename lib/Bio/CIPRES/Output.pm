package Bio::CIPRES::Output;

use 5.012;
use strict;
use warnings;

use Carp;
use XML::LibXML;
use Data::Dumper;

our $VERSION = 0.001;

sub new {

    my ($class, %args) = @_;

    my $self = bless {}, $class;

    croak "Must define job parent" if (! defined $args{parent});
    $self->{parent} = $args{parent};
    #TODO: check that $parent is of class BIO::CIPRES

    croak "Must define initial status" if (! defined $args{dom});
    $self->_parse_dom( $args{dom} );

    return $self;


}

sub _parse_dom {

    my ($self, $dom) = @_;

    # remove outer tag if necessary
    my $c = $dom->firstChild;
    $dom = $c if ($c->nodeName eq 'jobfile');

    $self->{handle}       = $dom->findvalue('jobHandle');
    $self->{name}         = $dom->findvalue('filename');
    $self->{length}       = $dom->findvalue('length');
    $self->{group}        = $dom->findvalue('parameterName');
    $self->{url_download} = $dom->findvalue('downloadUri/url');

    # check for missing values
    map {length $self->{$_} || croak "Missing value for $_\n"} keys %$self;

    return;

}

1;
