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
use constant BAD_INVOCATION    => 102;
use constant GENERIC_SVC_ERR   => 100;
use constant GENERIC_COMM_ERR  => 101;
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

    my 

    my $res = $job->download('name' => 'foobar');

    die $res if ($res->

    # you can do this, but it's probably faster just to pipe gunzip
    while (my $line = <$fh_bgz>) {
        print $line;
    }

    # here's the random-access goodness
    # fetch 32 bytes from uncompressed offset 1001
    seek $fh_bgz, 1001, 0;
    read $fh_bgz, my $data, 32;
    print $data;

    # Use as object
    my $reader = Compress::BGZF::Reader->new( $bgz_filename );

    # Move to a virtual offset (somehow pre-calculated) and read 32 bytes
    $reader->move_to_vo( $virt_offset );
    my $data = $reader->read_data(32);
    print $data;

    $reader->write_index( $fn_idx );

=head1 DESCRIPTION

C<Compress::BGZF::Reader> is a module implementing random access to the BGZIP file
format.  While it can do sequential/streaming reads, there is really no point
in using it for this purpose over standard GZIP tools/libraries, since BGZIP
is GZIP-compatible. The

There are two main modes of construction - as an object (using C<new()>) and
as a filehandle glob (using C<new_filehandle>). The filehandle mode is
straightforward for general use (emulating seek/read/tell functionality and
passing to other classes/methods that expect a filehandle).  The object mode
has additional features such as seeking to virtual offsets and dumping the
offset index to file.

=head1 METHODS

=head2 Filehandle Functions

=over 4

=item B<new_filehandle>

    my $fh_bgzf = Compress::BGZF::Writer->new_filehandle( $input_fn );

Create a new C<Compress::BGZF::Reader> engine and tie it to a IO::File handle,
which is returned. Takes a mandatory single argument for the filename to be
read from.

=item B<< <> >>

=item B<readline>

=item B<seek>

=item B<read>

=item B<tell>

=item B<eof>

    my $line = <$fh_bgzf>;
    my $line = readline $fh_bgzf;
    seek $fh_bgzf, 256, 0;
    read $fh_bgzf, my $buffer, 32;
    my $loc = tell $fh_bgzf;
    print "End of file\n" if eof($fh_bgzf);

These functions emulate the standard perl functions of the same name.

=back

=head2 Object-oriented Methods

=over 4

=item B<new>

    my $reader = Compress::BGZF::Reader->new( $fn_in );

Create a new C<Compress::BGZF::Reader> engine. Requires a single argument - the
name of the BGZIP file to be read from.

=item B<move_to>

    $reader->move_to( 493, 0 );

Seeks to the given uncompressed offset. Takes two arguments - the requested
offset and the relativity of the offset (0: file start, 1: current, 2: file end)

=item B<move_to_vo>

    $reader->move_to_vo( $virt_offset );

Like C<move_to>, but takes as a single argument a virtual offset. Virtual
offsets are described more in the top-level documentation for C<Compress::BGZF>.

=item B<get_vo>

    $reader->get_vo();

Returns the virtual offset of the current read position

=item B<read_data>

    my $data = $reader->read_data( 32 );

Read uncompressed data from the current location. Takes a single argument -
the number of bytes to be read - and returns the data read or C<undef> if at
C<EOF>.

=item B<getline>

    my $line = $reader->getline();

Reads one line of uncompressed data from the current location, shifting the
current file offset accordingly. Returns the line read or C<undef> if
currently at C<EOF>.

=item B<usize>

    my $size = $reader->usize();

Returns the uncompressed size of the file, as calculated during indexing.

=item B<write_index>

    $reader->write_index( $fn_index );

Writes the compressed index to file. The index format (as defined by htslib)
consists of little-endian int64-coded values. The first value is the number of
offsets in the index. The rest of the values consist of pairs of block offsets
relative to the compressed and uncompressed data. The first offset (always
0,0) is not included. The index files written by Compress::BGZF should be
compatible with those of the htslib C<bgzip> software, and vice versa.

=back

=head1 NEWLINES

Note that when using the tied filehandle interface, the behavior of the module
will replicate that of a file opened in raw mode. That is, none of the Perl
magic concerning platform-specific newline conversions will be performed. It's
expected that users of this module will generally be seeking to predetermined
byte offsets in a file (such as read from an index), and operations such as
C<seek>, C<read>, and C<< <> >> are not reliable in a cross-platform way on
files opened in 'text' mode. In other words, seeking to and reading from a
specific offset in 'text' mode may return different results depending on the
platform Perl is running on. This isn't an issue specific to this module but
to Perl in general. Users should simply be aware that any data read using this
module will retain its original line endings, which may not be the same as
those of the current platform.

For a further discussion, see
L<http://perldoc.perl.org/perlport.html#Newlines>.

=head1 CAVEATS AND BUGS

This is code is in alpha testing stage and the API is not guaranteed to be
stable.

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jdv *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2015-2016 Jeremy Volkening

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

