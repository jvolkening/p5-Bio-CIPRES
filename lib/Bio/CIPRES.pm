package Bio::CIPRES;

use 5.012;
use strict;
use warnings;

use Carp;
use Config::Tiny;
use List::Util qw/first/;
use LWP;
use URI;
use URI::Escape;
use XML::LibXML;

use Bio::CIPRES::Job;
use Bio::CIPRES::Error;

our $VERSION = 0.002;
our $UA      = 'Bio::CIPRES';
our $SERVER  = 'cipresrest.sdsc.edu';
our $API     = 'cipresrest/v1';
our $DOMAIN  = 'Cipres Authentication';

my %defaults = (
    url     => "https://$SERVER/$API/",
    timeout => 60,
    app_id  => 'cipres_perl-E9B8D52FA2A54472BF13F25E4CD957D4',
    user    => undef,
    pass    => undef,
);

sub new {

    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # parse properties from file or constructor
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
    $self->{agent}->credentials(
        $netloc,
        $DOMAIN,
        $self->{cfg}->{user},
        $self->{cfg}->{pass}
    );

    return $self;

}

sub _parse_args {

    my ($self, %args) = @_;
    my ($fn_cfg) = delete $args{conf};

    # set defaults
    $self->{cfg} = {%defaults}; # copy, don't reference!

    # read from config file if asked, overwriting defaults
    if (defined $fn_cfg) {
        croak "Invalid or missing configuration file specified"
            if (! -e $fn_cfg);
        my $cfg = Config::Tiny->read( $fn_cfg )
            or croak "Error reading configuration file: $@";
        $self->{cfg}->{$_} = $cfg->{_}->{$_}
            for (keys %{ $cfg->{_} });

    }

    # read parameters from constructor, overwriting if present
    $self->{cfg}->{$_} = $args{$_} for (keys %args);

    # check that all defined fields are valid
    my @extra = grep {! exists $defaults{$_}} keys %{ $self->{cfg} };
    croak "Unexpected config variables found (@extra) -- check syntax"
        if (scalar @extra);

    # check that all required fields are defined
    my @missing = grep {! defined $self->{cfg}->{$_}} keys %defaults;
    croak "Required config variables missing (@missing) -- check syntax"
        if (scalar @missing);

    # TODO: further parameter validation ???
  
    # Do necessary url-encoding
    for (qw/user pass/) {
        $self->{cfg}->{$_} =  uri_escape( $self->{cfg}->{$_} );
    }
   
    # add auth info to string
    $self->{uri} = URI->new( $self->{cfg}->{url} );

}

sub list_jobs {

    my ($self) = @_;

    my $res = $self->_get(
        "$self->{uri}/job/$self->{cfg}->{user}?expand=true"
    );

    my $dom = XML::LibXML->load_xml('string' => $res);
    return map {
        Bio::CIPRES::Job->new( agent => $self->{agent}, dom => $_ )
    } $dom->findnodes('/joblist/jobs/jobstatus');

}

sub get_job {

    my ($self, $handle) = @_;
    my $res = $self->_get(
        "$self->{uri}/job/$self->{cfg}->{user}/$handle"
    );

    my $dom = XML::LibXML->load_xml('string' => $res);
    return Bio::CIPRES::Job->new(
        agent => $self->{agent},
        dom   => $dom,
    );

}

sub submit_job {

    my ($self, @args) = @_;

    my $res = $self->_post(
        "$self->{uri}/job/$self->{cfg}->{user}",
        @args,
    );

    my $dom = XML::LibXML->load_xml('string' => $res);
    return Bio::CIPRES::Job->new(
        agent => $self->{agent},
        dom   => $dom,
    );

}

sub _get {

    my ($self, $url) = @_;

    my $res = $self->{agent}->get( $url )
        or croak "Error fetching file from $url: $@";

    die Bio::CIPRES::Error->new( $res->content )
        if (! $res->is_success);

    return $res->content;

}

sub _post {

    my ($self, $url, @args) = @_;

    my $res = $self->{agent}->post(
        $url,
        [ @args ],
        'content_type' => 'form-data',
    ) or croak "Error POSTing to $url: $@";

    die Bio::CIPRES::Error->new( $res->content )
        if (! $res->is_success);

    return $res->content;

}

1;


__END__

=head1 NAME

Bio::CIPRES - interface to the CIPRES REST API

=head1 SYNOPSIS

    use Bio::CIPRES;

    my $ua = Bio::CIPRES->new(
        user    => $username,
        pass    => $password,
        app_id  => $id,
        timeout => 60,
    );

    my $job = $ua->submit_job( %job_params );

    while (! $job->is_finished) {
        sleep $job->poll_interval;
        $job->refresh;
    }

    print STDOUT $job->stdout;
    print STDERR $job->stderr;

    if ($job->exit_code == 0) {

        for my $file ($job->outputs) {
            $file->download( out => $file->name );
        }

    }
    

=head1 DESCRIPTION

C<Bio::CIPRES> is an interface to the CIPRES REST API for running phylogenetic
analyses. Currently it provides general classes and methods for job submission
and handling - determination of the correct parameters to submit is up to the
user (check L<SEE ALSO> for links to tool documentation).

=head1 METHODS

=over 4

=item B<new>

    my $ua = Bio::CIPRES->new(
        user    => $username,
        pass    => $password,
        app_id  => $id,
        timeout => 60,
    );

    # or read configuration from file

    my $ua = Bio::CIPRES->new(
        conf => "$ENV{HOME}/.cipres"
    );

Create a new C<Bio::CIPRES> object. There are three required parameters:
username (C<user>), passphrase (C<pass>), and application ID (C<app_id>).
These can either be passed in on the constructor or read in from a
configuration file, as demonstrated above. The configuration file should
contain key=value pairs, one pair per line, as in:

    user=foo
    pass=bar
    app_id=foo_bar_baz

The passphrase must be stored in plaintext, so the usual precautions apply
(e.g. the file should not be world-readable). If possible, find another way to
retrieve the passphrase within your code and pass it in directly as a method
argument.

=item B<submit_job>

    my $job = $ua->submit_job( %params );

Submit a new job to the CIPRES service. Params are set based on the tool
documentation (not covered here). Returns a L<Bio::CIPRES::Job> object.

Most params are passed as simple key => value pairs of strings based on the
CIPRES tool documentation. B<One important nuance>, however, is in the
handling of input files. If the contents of a input file are to be passed in
as a scalar, they should be provided directly as the scalar value to the
appropriate key:

    my $job = $ua->submit_job( 'input.infile_' => $in_contents );

However, if the input file is to be uploaded by filename, it should be passed
as an array reference:

    my $job = $ua->submit_job( 'input.infile_' => [$in_filename] );

Failure to understand the difference will result in errors either during job
submission or during the job run.

=item B<list_jobs>

    for my $job ( $ua->list_jobs ) {
        # do something
    }

Returns an array of L<Bio::CIPRES::Job> objects representing jobs in the
user's workspace.

=item B<get_job>

    my $job = $ua->get_job( $job_handle );

Takes a single argument (string containing the job handle/ID) and returns a
L<Bio::CIPRES::Job> object representing the appropriate job, or undef if not
found.

=back

=head1 CAVEATS AND BUGS

This is code is in alpha testing stage and the API is not guaranteed to be
stable.

Currently the use of UMBRELLA authentication is not implemented.

Please report bugs to the author.

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

