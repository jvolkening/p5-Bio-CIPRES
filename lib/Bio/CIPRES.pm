package Bio::CIPRES;

use 5.012;
use strict;
use warnings;

use Carp;
use Config::Tiny;
use LWP;
use URI;
use URI::Escape;

our $VERSION = 0.001;
our $UA      = 'Bio::CIPRES';

my %defaults = (
    url     => 'https://cipresrest.sdsc.edu/cipresrest/v1/',
    timeout => 60,
    user    => undef,
    pass    => undef,
    app_id  => undef,
);

sub new {

    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # parse arguments from file or constructor
    $self->_parse_args(%args);

    # setup user agent
    $self->{agent} = LWP::UserAgent->new(
        agent    => "$UA/$VERSION",
        ssl_opts => {verify_hostname => 0},
        timeout  => $self->{cfg}->{timeout},
    );
    $self->{agent}->default_header(
        'cipres-appkey' => $self->{cfg}->{app_id}
    );
    my $netloc = join ':', $self->{uri}->host, $self->{uri}->port;
    warn "NL: $netloc\n";
    $self->{agent}->credentials(
        $netloc,
        'Cipres Authentication',
        $self->{cfg}->{user},
        $self->{cfg}->{pass}
    );

    return $self;


}

sub _parse_args {

    my ($self, %args) = @_;
    my ($fn_cfg) = delete $args{conf};

    # set defaults
    $self->{cfg} = {%defaults};

    # read from config file if asked
    if (defined $fn_cfg) {
        croak "Invalid or missing configuration file specified"
            if (! -e $fn_cfg);
        my $cfg = Config::Tiny->read( $fn_cfg )
            or croak "Error reading configuration file: $@";
        $self->{cfg}->{$_} = $cfg->{_}->{$_}
            for (keys %{ $cfg->{_} });

    }

    # read fields from constructor, overwriting if present
    $self->{cfg}->{$_} = $args{$_}
        for (keys %args);

    # check that all fields are valid and defined
    my @extra = grep {! exists $defaults{$_}} keys %{ $self->{cfg} };
    croak "Unexpected config variables found (@extra) -- check syntax"
        if (scalar @extra);
    my @missing = grep {! defined $self->{cfg}->{$_}} keys %defaults;
    croak "Required config variables missing (@missing) -- check syntax"
        if (scalar @missing);

    # TODO: further parameter validation ???
    
    $self->{cfg}->{user} =  uri_escape( $self->{cfg}->{user} );
    $self->{cfg}->{pass} =  uri_escape( $self->{cfg}->{pass} );
   
    # add auth info to string
    my $uri = URI->new( $self->{cfg}->{url} );
    $self->{uri} = $uri;

}

sub list_jobs {

    my ($self) = @_;

    my $res = $self->{agent}->get("$self->{uri}/job/$self->{cfg}->{user}");
    print $res->code, "\n";
    print $res->content;

}

sub submit_job {

    my ($self, $tool, $file, $id, $name, $email) = @_;

    my $res = $self->{agent}->post(
        "$self->{uri}/job/$self->{cfg}->{user}",
        {
            'tool'          => $tool,
            'input.infile_' => $file,
            'metadata.clientJobId' => $id,
            'metadata.clientJobName' => $name,
            'metadata.clientToolName' => "FOO $tool",
            'metadata.statusEmail' => 'true',
            'metadata.emailAddress' => $email,
        },
        'content_type' => 'form-data',
    );
    print $res->code;
    print $res->content;

}

1;


__END__

=head1 NAME

Bio::CIPRES - interface to the CIPRES REST API

=head1 SYNOPSIS

    use BioX::Seq;

    my $seq = BioX::Seq->new();

    for (qw/AATG TAGG CCAT TTGA/) {
        $seq .= $_;
    }

    $seq->id( 'test_seq' );

    my $rc = $seq->rev_com(); # original untouched
    print $seq->as_fasta();

    # >test_seq
    # AATGTAGGCCATTTGA

    $seq->rev_com(); # original modified in-place
    print $seq->as_fastq(22);

    # @test_seq
    # TCAAATGGCCTACATT
    # +
    # 7777777777777777

    print $seq->range(3,6)->as_fasta();

    # >test_seq
    # AAAT

=head1 DESCRIPTION

C<BioX::Seq> is a simple sequence class that can be used to represent
biological sequences. It was designed as a compromise between using simple
strings and hashes to hold sequences and using the rather bloated objects of
Bioperl. Features (or, depending on your viewpoint, bugs) include
auto-stringification and context-dependent transformations. It is meant
be used primarily as the return object of the C<BioX::Seq::Fastx> parser, but
there may be occasions where it is useful in its own right.

C<BioX::Seq> current implements a small subset of the transformations most
commonly used by the author (reverse complement, translate, subrange) - more
methods may be added in the future as use suggests and time permits, but the
core object will be kept as simple as possible and should be limited to the
four current properties - sequence, ID, description, and quality - that
satisfy 99% of the author's needs.

Some design decisions have been made for the sake of speed over ease of use.
For instance, there is no sanity-checking of the object properties upon
creation of a new object or use of the accessor methods. Parameters to the
constructor are positional rather than named (testing indicates that this
reduces execution times by ~ 40%). 

=head1 METHODS

=over 4

=item B<new>

=item B<new> I<SEQUENCE>

=item B<new> I<SEQUENCE> I<ID>

=item B<new> I<SEQUENCE> I<ID> I<DESCRIPTION>

=item B<new> I<SEQUENCE> I<ID> I<DESCRIPTION> I<QUALITY>

Create a new C<BioX::Seq> object (empty by default). All arguments are optional
but are positional and, if provided, must be given in order.

    $seq = BioX::Seq->new( SEQ, ID, DESC, QUALITY );

Returns a new C<BioX::Seq> object.

=item B<seq>, B<id>, B<desc>, B<qual>

Accessors to the object properties named accordingly. Properties can also be
accessed directly as hash keys. This is probably frowned upon by some, but can be
useful at times e.g. to perform substution on a property in-place.

    $seq->{id} =~ s/^Unnecessary_prefix//;

Takes zero or one arguments. If an argument is given, assigns that value to the
property in question. Returns the current value of the property.

=item B<range> I<START> I<END>

Extract a subsequence from I<START> to I<END>. Coordinates are 1-based.

Returns a new BioX::Seq object, or I<undef> if the coordinates are outside the
limits of the parent sequence.

=item B<rev_com>

Reverse complement the sequence.

Behavior is context-dependent. In scalar or list context, returns a new
BioX::Seq object containing the reverse-complemented sequence, leaving the
original sequence untouched. In void context, updates the original sequence
in-place and returns TRUE if successful.

=item B<translate>

=item B<translate> I<FRAME>

Translate a nucleic acid sequence to a peptide sequence.

I<FRAME> specifies the starting point of the translation. The default is zero.
A I<FRAME> value of 0-2 will return the translation of each of the three
forward reading frames, respectively, while a value of 3-5 will return the
translation of each of the three reverse reading frames, respectively.

=item B<as_fasta>

=item B<as_fasta> I<LINE_LENGTH>

Returns a string representation of the sequence in FASTA format. Requires
that, at a minimum, the <seq> and <id> properties be defined. I<LINE_LENGTH>,
if given, specifies the line length for wrapping purposes (default: 60).

=item B<as_fastq>

=item B<as_fastq> I<DEFAULT_QUALITY>

Returns a string representation of the sequence in FASTQ format. Requires
that, at a minimum, the <seq> and <id> properties be defined.
I<DEFAULT_QUALITY>, if given, specifies the default Phred quality score to be
assigned to each base if missing - for instance, if converting from FASTA to
FASTQ (default: 20).

=back

=head1 CAVEATS AND BUGS

No input validation is performed during construction or modification of the
object properties.

Performing certain operations (for instance, s///) on a BioX::Seq object
relying on auto-stringification may convert the object into a simple unblessed
scalar containing the sequence string. You will likely know if this happens
(you are using strict and using warnings, right?) because your script will
throw an error if you try to perform a class method on the (now) unblessed
scalar.

Please report bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jeremy *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2014 Jeremy Volkening

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

