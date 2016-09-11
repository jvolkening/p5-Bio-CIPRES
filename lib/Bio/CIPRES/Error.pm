package Bio::CIPRES::Error 0.001;

use 5.012;

use strict;
use warnings;

use overload
    'bool'   => sub {return 0},
    '0+'     => sub {return $_[0]->{code}},
    '""'     => \&stringify,
    fallback => 1;

use Carp;
use XML::LibXML;

# Error codes
use constant AUTHORIZATION     => 1;
use constant AUTHENTICATION    => 2;
use constant NOT_FOUND         => 4;
use constant FORM_VALIDATION   => 5;
use constant USER_MISMATCH     => 6;
use constant BAD_REQUEST       => 7;
use constant GENERIC_SVC_ERR   => 100;
use constant GENERIC_COMM_ERR  => 101;
use constant BAD_INVOCATION    => 102;
use constant USAGE_LIMT        => 103;
use constant DISABLED_RESOURCE => 104;

sub new {

    my ($class, $xml) = @_;

    my $self = bless {}, $class;
    croak "Undefined XML string in constructor\n" if (! defined $xml);
    $self->_parse_xml( $xml );

    return $self;

}

sub stringify {

    my ($self) = @_;

    return join ' : ', $self->{display},
        map {"Error in param \"$_->{param}\" ($_->{error})"}
        @{ $self->{param_errors} };

}

sub _parse_xml {

    my ($self, $xml) = @_;

    my $dom = XML::LibXML->load_xml('string' => $xml)
        or croak "Error parsing error XML: $!";

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

sub is_error { return 1; }

1;

__END__

=head1 NAME

Bio::CIPRES::Error - A simple error object for the CIPRES API

=head1 SYNOPSIS

    use Bio::CIPRES;

    my $res = $job->download('name' => 'foobar')
        or die "$res";

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

