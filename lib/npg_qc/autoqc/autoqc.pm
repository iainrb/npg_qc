package npg_qc::autoqc::autoqc;

use Moose;
use namespace::autoclean;
use Class::Load qw(load_class);
use Carp;
use Readonly;
use File::Spec;
use List::Util qw(first);

use npg_tracking::util::types;

with  qw / npg_tracking::illumina::run::short_info
           npg_tracking::illumina::run::folder
           MooseX::Getopt
         /;

our $VERSION = '0';
## no critic (Documentation::RequirePodAtEnd)

=head1 NAME

npg_qc::autoqc::autoqc

=head1 SYNOPSIS

  my $aqc = npg_qc::autoqc::autoqc->new(archive_path=>q[some_path], position=>1, check=>q[insert_size]);
  $aqc->run();

=head1 DESCRIPTION

A wrapper around autoqc check libraries.

=head1 SUBROUTINES/METHODS

=cut

Readonly::Scalar my $CHECKS_NAMESPACE    => q[npg_qc::autoqc::checks];
Readonly::Scalar my $NO_TAG_INDEX        => -1;

=head2 tag_index

Tag index for a plex, does not have to be set.

=cut
has 'tag_index'    => (isa       => 'Int',
                       is        => 'ro',
                       required  => 0,
                       documentation => 'tag index, an integer betwee 0 and some large number, see npg_tracking::glossary::tag',
                      );


=head2 check

The name of the check to perform.

=cut
has 'check'    => (isa      => 'Str',
                   is       => 'ro',
                   required => 1,
                   documentation => 'QC check name',
                  );

=head2 position

Lane number.
0000000
=cut
has 'position' => (isa      => 'NpgTrackingLaneNumber',
                   is       => 'ro',
                   required => 1,
                   documentation => 'Lane (position) number.',
                  );

=head2 repository

An absolute path to the current reference repository.

=cut
has 'repository'       => (isa =>'Str', is => 'ro', required  => 0,
                           documentation => 'Path to teh directory with ref repository and adapters',);
has 'reference_genome' => ( isa => 'Str', is => 'ro', required => 0,
                            documentation => 'Reference genome as defined in LIMS objects.',);
has 'species'          => ( isa => 'Str', is => 'ro', required => 0,
                            documentation => 'Species name as used in the reference repository. No synonyms please.',);
has 'strain'           => ( isa => 'Str', is => 'ro', required => 0,
                            documentation => 'Strain as used in the reference repository.',);

=head2 qc_in

Path to a directory where the fastq and similar files for the check are found

=cut
has 'qc_in'       => (isa       => 'Str',
                      is        => 'ro',
                      required  => 0,
                      predicate => '_has_qc_in',
                      writer    => '_write_qc_in',
                      documentation => 'Path to a directory where the fastq and similar files for the check are found.',
                     );

=head2 file_type

Type of input file (fastq or bam).

=cut
has 'file_type'   => (isa       => 'Str',
                      is        => 'ro',
                      required  => 0,
                      documentation => 'Type of input file (fastq or bam).',
                     );

=head2 qc_out

Path to a directory where the results should be written to

=cut
has 'qc_out'      => (isa       => 'Str',
                      is        => 'ro',
                      required  => 0,
                      predicate => '_has_qc_out',
                      writer    => '_write_qc_out',
                      documentation => 'Path to a directory where the results should be written to.',
                     );


sub _build_run_folder {
    my $self = shift;
    return first {$_ ne q()} reverse File::Spec->splitdir($self->runfolder_path);
}

=head2 BUILD

build method

=cut

sub BUILD {
    my $self = shift;

    if ($self->_has_qc_in) {
        if (!$self->_has_qc_out) {
            $self->_write_qc_out($self->qc_in);
        }
    } else {
        if ($self->check() eq 'spatial_filter') {
            $self->_write_qc_in('/dev/stdin'); #horrid - need to rethink this object and bin/qc
        } elsif (defined $self->tag_index) {
            $self->_write_qc_in($self->lane_archive_path($self->position));
        } else {
            $self->_write_qc_in($self->archive_path);
        }
        if (!$self->_has_qc_out) {
            if (defined $self->tag_index) {
                $self->_write_qc_out($self->lane_qc_path($self->position));
            } else {
                $self->_write_qc_out($self->qc_path);
            }
        }
    }
    if (!-R $self->qc_in) {
        croak q[Input qc directory ] . $self->qc_in . q[ does not exist or is not readable];
    }
    if (!-W $self->qc_out) {
        croak q[Output qc directory ] . $self->qc_out . q[ does not exist or is not writable];
    }
    return;
}

sub _create_test_object {
    my $self = shift;

    my $pkg = $CHECKS_NAMESPACE . q[::] . $self->check;
    load_class($pkg);
    my $init = {
                path      => $self->qc_in,
                position  => $self->position,
                id_run    => $self->id_run,
                 };

    my @attrs = qw/tag_index repository reference_genome species strain file_type/;
    foreach my $attr_name (@attrs) {
        if ($attr_name eq q[tag_index] ) {
            if (defined $self->$attr_name) {
                $init->{$attr_name} = $self->$attr_name;
            }
        } else {
            if ($self->$attr_name) {
                $init->{$attr_name} = $self->$attr_name;
            }
        }
    }
    return $pkg->new($init);
}


=head2 run

Creates an object that can perform the requested test, calls test execution and writes out test results to the output folder.

=cut
sub run {
    my $self = shift;

    if (!-e $self->qc_out) {
        croak q[Destination directory for qc results ] . $self->qc_out . q[ does not exist];
    }

    my $check = $self->_create_test_object();
    $check->execute();
    $check->result->store($self->qc_out);

    return 1;
}


=head2 can_run

Checks whether a check can be executed for a particular run.
If there are any problems with this test, returns 1.

=cut
sub can_run {
    my $self = shift;
    return $self->_create_test_object()->can_run;
}

no MooseX::ClassAttribute;
__PACKAGE__->meta->make_immutable;

1;
__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item namespace::autoclean

=item MooseX::ClassAttribute

=item Class::Load

=item File::Spec

=item Carp

=item Readonly

=item List::Util

=item npg_tracking::illumina::run::short_info

=item npg_tracking::illumina::run::folder

=item npg_tracking::util::types

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Marina Gourtovaia E<lt>mg8@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016 GRL

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
