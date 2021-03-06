package npg_qc_viewer::Model::MLWarehouseDB;

use Moose;
use namespace::autoclean;
use Carp;

use npg_qc_viewer::Util::TransferObject;

BEGIN { extends 'Catalyst::Model::DBIC::Schema' }

our $VERSION  = '0';

## no critic (Documentation::RequirePodAtEnd)

=begin stopwords

lims

=end stopwords

=head1 NAME

npg_qc_viewer::Model::MLWarehouseDB

=head1 SYNOPSIS

=head1 DESCRIPTION

Catalyst::Model::DBIC::Schema Model using schema WTSI::DNAP::Warehouse::Schema

=head1 SUBROUTINES/METHODS

=cut

__PACKAGE__->config(
  schema_class => 'WTSI::DNAP::Warehouse::Schema',
  connect_info => [], #a fall-back position if connect_info is not defined in the config file
);

=head2 search_product_metrics

Search product metrics by id_run and, optionally, position and tag_index.
Cache option is enabled.

  my $param = {'id_run' => 22, 'position' => 3};
  my $resultset = $model->search_product_metrics($param);

  my $param = {'id_run' => 22, 'position' => 3, 'tag_index' => 5};
  my $resultset = $model->search_product_metrics($param);

=cut
sub search_product_metrics {
  my ($self, $run_details) = @_;

  if(!defined $run_details){
    croak q[Conditions were not provided for search];
  }
  if(!$run_details->{'id_run'}) {
    croak q[Run id needed];
  }

  my $where = {};
  foreach my $key (keys %{$run_details}) {
    $where->{q[me.] . $key} = $run_details->{$key};
  }

  my $rs = $self->resultset('IseqProductMetric')->search(
        $where, {
        'prefetch' => ['iseq_run_lane_metric', {'iseq_flowcell' => ['study', 'sample']}],
        'order_by' => [qw/ me.id_run me.position me.tag_index /],
        'cache'    => 1,
                });

  return $rs;
}

=head2 search_product_by_id_library_lims

Search product id library lims.

=cut
sub search_product_by_id_library_lims {
  my ($self, $id_library_lims) = @_;

  if (!defined $id_library_lims) {
    croak q[Id library lims not defined when querying library lims];
  }

  my $where = { 'iseq_flowcell.id_library_lims' => $id_library_lims, };

  return $self->_search_product_by_child_id($where);
}

=head2 search_product_by_id_pool_lims

Search for product by id pool lims.

=cut
sub search_product_by_id_pool_lims {
  my ($self, $id_pool_lims) = @_;

  if (!defined $id_pool_lims) {
    croak q[Id pool lims not defined when querying pool lims];
  }

  my $where = { 'iseq_flowcell.id_pool_lims' => $id_pool_lims, };

  return $self->_search_product_by_child_id($where);
}

=head2 search_product_by_sample_id

Search product by id sample lims

=cut
sub search_product_by_sample_id {
  my ($self, $id_sample_lims) = @_;

  if (!defined $id_sample_lims) {
    croak q[Id sample lims not defined when querying sample lims];
  };

  my $where = { 'sample.id_sample_lims' => $id_sample_lims, };

  return $self->_search_product_by_child_id($where);
}

sub _search_product_by_child_id {
  my ($self, $where) = @_;

  if (!defined $where) {
    croak q[Condition for id lims not defined when querying product by children id];
  };

  my $rs = $self->resultset('IseqProductMetric')->search(
                    $where, {
                    'prefetch' => {'iseq_flowcell' => 'sample'},
                    'join'     => {'iseq_flowcell' => 'sample'},
                    'cache'    => 1,
                            });

  return $rs;
}

=head2 search_sample_by_sample_id

Search sample by id sample lims

=cut
sub search_sample_by_sample_id {
  my ($self, $id_sample_lims) = @_;

  if (!defined $id_sample_lims) {
    croak q[Id sample lims not defined when querying sample lims];
  };

  my $resultset = $self->resultset('Sample');
  my $cs_alias = $resultset->current_source_alias;

  my $where = { $cs_alias . '.id_sample_lims' => $id_sample_lims, };

  my $rs = $self->resultset('Sample')->
                    search($where, {'cache' => 1});

  return $rs;
}

=head2 tags4lane

An array of tag indexes that are subject to qc is returned.

  $model->tags4lane({'id_run' => 4, 'position' => 4});

=cut
sub tags4lane {
  my ($self, $lane_hash) = @_;

  my $rs = $self->resultset('IseqProductMetric')->search(
    {
      'me.id_run'     => $lane_hash->{'id_run'},
      'me.position'   => $lane_hash->{'position'},
    },
    {
      'join'     => 'iseq_flowcell',
      'order_by' => [qw/ me.tag_index /],
      'cache'    => 1,
    }
  );
  if ($rs->count == 0) {
    croak sprintf 'No NPG mlwarehouse data for run %i position %i',
      $lane_hash->{'id_run'}, $lane_hash->{'position'};
  }

  my @tags = ();
  while (my $row = $rs->next) {
    my $tag_index = $row->tag_index;
    if (!$tag_index) {
      next;
    }
    my $flowcell_row = $row->iseq_flowcell;
    if (!$flowcell_row) {
      croak sprintf 'Flowcell data missing for run %i position %i tag_index %i',
                    $lane_hash->{'id_run'}, $lane_hash->{'position'}, $tag_index;
    }
    my $from_gclp  = $flowcell_row->from_gclp()  ? 1 : 0;
    my $is_control = $flowcell_row->is_control() ? 1 : 0;
    if (npg_qc_viewer::Util::TransferObject->qc_able(
        $from_gclp, $is_control, $tag_index)) {
      push @tags, $tag_index;
    }
  }

  return \@tags;
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

=item Catalyst::Model::DBIC::Schema

=item Carp

=item WTSI::DNAP::Warehouse::Schema

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

David Jackson

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016 Genome Research Ltd.

This file is part of NPG software.

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
