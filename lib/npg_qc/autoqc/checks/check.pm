package npg_qc::autoqc::checks::check;

use Moose;
use namespace::autoclean;
use Class::Load qw(load_class);
use Carp;
use File::Basename;
use File::Spec::Functions qw(catfile);
use File::Temp qw(tempdir);
use Readonly;

use npg_tracking::util::types;

with qw/ npg_tracking::glossary::run
         npg_tracking::glossary::lane
         npg_tracking::glossary::tag /;

our $VERSION = '0';
## no critic (Documentation::RequirePodAtEnd ProhibitParensWithBuiltins ProhibitStringySplit)

=head1 NAME

npg_qc::autoqc::checks::check

=head1 SYNOPSIS

  my $check = npg_qc::autoqc::checks::check->new(path => q[a/valid/path], position => 1, id_run => 2222);

=head1 DESCRIPTION

A parent class for autoqc checks. Checks are performed either for a lane or for a plex(index,lanelet).

=head1 SUBROUTINES/METHODS

=cut

Readonly::Scalar our $FILE_EXTENSION  => 'fastq';

=head2 path

A path to a directory with input files. Read-only.

=cut
has 'path'        => (isa      => 'Str',
                      is       => 'ro',
                      required => 1,
                     );

=head2 position

Lane number. An integer from 1 to 8 inclusive.

=head2 id_run

Run id for the lane to be checked.

=head2 tag_index

An optional tag index

=head2 tmp_path

A path to a directory that can be used by the check to write temporary files to.
By default, a temporary directory in a usual place for temporary files (/tmp on Linux)
will be created and deleted automatically on exit.

=cut
has 'tmp_path'    => (isa        => 'Str',
                      is         => 'ro',
                      required   => 0,
                      default    => sub { return tempdir(CLEANUP => 1); },
                     );

=head2 file_type

File type, also input file extension.

=cut
has 'file_type' => (isa        => 'Str',
                    is         => 'ro',
                    required   => 0,
                    default    => $FILE_EXTENSION,
                   );

=head2 input_file

A ref to a list with names of input files for this check

=cut
has 'input_files'    => (isa        => 'ArrayRef',
                         is         => 'ro',
                         required   => 0,
                         lazy_build => 1,
                        );
sub _build_input_files {
    my $self = shift;
    my @files = $self->get_input_files();
    return \@files;
}

=head2 result

A result object. Read-only.

=cut
has 'result'     =>  (isa        => 'Object',
                      is         => 'ro',
                      required   => 0,
                      lazy_build => 1,
                     );
sub _build_result {
    my $self = shift;

    my $pkg_name = ref $self;
    ## no critic (TestingAndDebugging::ProhibitNoStrict ValuesAndExpressions::ProhibitInterpolationOfLiterals)
    no strict 'refs';
    my $module_version = ${$pkg_name."::VERSION"};
    use strict;
    ## use critic

    my ($ref) = ($pkg_name) =~ /(\w*)$/smx;
    if ($ref eq q[check]) {
        $ref =  q[result];
    }
    my $module = "npg_qc::autoqc::results::$ref";
    load_class($module);

    my $nref = { id_run => $self->id_run, position => $self->position, };
    $nref->{'path'} = $self->path;
    if (defined $self->tag_index) {
        # In newish Moose undefined but set tag index is serialized to json,
        # which is not good for result objects that do hot have tag_index db column
        $nref->{'tag_index'} = $self->tag_index;
    }
    my $result = $module->new($nref);

    $result->set_info('Check', $pkg_name);
    $result->set_info('Check_version', $module_version);
    return $result;
}

=head2 execute

The actual test should implement this method.
Here this method only checks that the given path exists.

=cut
sub execute {
    my $self = shift;
    if (!$self->path)     {croak q[No input files directory supplied];}
    if (!-e $self->path)  {croak q[Input files directory ] . $self->path() . q[ does not exist];}
    if (!@{$self->input_files}) {
        return 0;
    }
    return 1;
}

=head2 can_run

Decides whether this check can be run for a particular run.

=cut
sub can_run {
    return 1;
}

=head2 get_input_files

Returns an array containing full paths to a forward and reverse(if any) input files.

=cut
sub get_input_files {
    my $self = shift;

    my @fnames = ();
    my $forward = join q[.], catfile($self->path, $self->create_filename($self, 1)),
                             $self->file_type;
    my $no_end_forward = undef;
    if (!-e $forward) {
        $no_end_forward = join q[.], catfile($self->path, $self->create_filename($self)),
                                     $self->file_type;
        if (-e $no_end_forward) {
           $forward = $no_end_forward;
        } else {
           $self->result->comments(qq[Neither $forward nor $no_end_forward file found]);
           return @fnames;
        }
    }

    push @fnames, $forward;
    if (!defined $no_end_forward) {
        my $reverse =  join q[.], catfile($self->path, $self->create_filename($self, 2)),
                                  $self->file_type;
        if (-e $reverse) {push @fnames, $reverse;}
    }

    return @fnames;
}

=head2 generate_filename_attr

Gets an array containing paths to forward and reverse (if any) input files, and returns
an array ref with file names that is suitable for setting the filename attribute.

=cut
sub generate_filename_attr {
    my $self = shift;
    my @filenames = ();
    foreach my $fname (@{$self->input_files}) {
        my($name, $directories, $suffix) = fileparse($fname);
        push @filenames, $name;
    }
    return \@filenames;
}

=head2 overall_pass

If the evaluation is performed separately for a forward and a reverse sequence,
computes overall lane pass value for a particular check.

=cut
sub overall_pass {
    my ($self, $apass, $count) = @_;
    if ($apass->[0] != 1 || $count == 1) {return $apass->[0];}
    if ($apass->[1] != 1) {return $apass->[1];}
    return ($apass->[0] && $apass->[1]);
}

=head2 create_filename - given run id, position, tag index (optional) and end (optional)
returns a file name

  npg_qc::autoqc::checks::check->create_filename({id_run=>1,position=>2,tag_index=>3},2);
  $obj->create_filename({id_run=>1,position=>2},1);
=cut
sub create_filename {
    my ($self, $map, $end) = @_;

    return sprintf '%i_%i%s%s',
        $map->{'id_run'},
        $map->{'position'},
        $end ? "_$end" : q[],
        defined $map->{'tag_index'} ? q[#].$map->{'tag_index'} : q[];
}

__PACKAGE__->meta->make_immutable;

1;
__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item namespace::autoclean

=item Class::Load

=item Carp

=item Readonly

=item File::Basename

=item File::Spec::Functions

=item File::Temp

=item npg_tracking::glossary::run

=item npg_tracking::glossary::lane

=item npg_tracking::glossary::tag

=item npg_tracking::util::types

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Marina Gourtovaia E<lt>mg8@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 GRL

This file is part of NPG.

NPG is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
