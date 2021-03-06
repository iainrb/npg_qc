use strict;
use warnings;
use Test::More tests => 13;
use Test::Exception;
use Test::Deep;
use Moose::Meta::Class;
use JSON;
use npg_testing::db;

use_ok('npg_qc::Schema::Result::VerifyBamId');

my $schema = Moose::Meta::Class->create_anon_class(
          roles => [qw/npg_testing::db/])
          ->new_object({})->create_test_db(q[npg_qc::Schema]);

my $json =
q {
{
 "avg_depth":1.41,
 "freeLK0":815501.89,
 "freeLK1":815503.15,
 "freemix":0,
 "id_run":"7321",
 "info":{"Check":"npg_qc::autoqc::checks::verify_bam_id","Check_version":"58.0","Verifier":"verifyBamID","Verify_options":" --bam in/7321_7#5.bam --vcf /lustre/scratch110/srpipe/population_snv/Homo_sapiens/1000G_Omni25_genotypes_2141/Standard/1000Genomes/Standard-1000Genomes.vcf.gz --self --ignoreRG --minQ 20 --minAF 0.05 --maxDepth 500 --precise --out /tmp/lew2Twr019/7321_7#5.bam"},
 "number_of_reads":1908387,
 "number_of_snps":1351960,
 "path":"in",
 "position":"7",
 "tag_index":"5"}
};

my $values = from_json($json);
my $rs = $schema->resultset('VerifyBamId');
isa_ok($rs->new_result($values), 'npg_qc::Schema::Result::VerifyBamId');

{
  my %values1 = %{$values};
  my $v1 = \%values1;

  $rs->deflate_unique_key_components($v1);
  is($v1->{'tag_index'}, 5, 'tag index deflated');
  lives_ok {$rs->find_or_new($v1)->set_inflated_columns($v1)->update_or_insert()}
    'lane record inserted';
  my $rs1 = $rs->search({});
  is($rs1->count, 1, q[one row created in the table]);
  my $row = $rs1->next;
  is($row->tag_index, 5, 'tag index inflated');
  is(ref $row->info, 'HASH', 'info returned as hash ref');
  cmp_deeply($row->info, $values->{'info'},
    'info hash content is correct');
  is($row->freeLK0, 815501.89, 'can use method as the name of the column');
  is($row->freeLK1, 815503.15, 'can use method as the name of the column');
  is($row->avg_depth, 1.41, 'depth retrieved correctly');
  $rs1->delete_all;
}

subtest 'Result with default criterion' => sub{
  plan tests => 5;

  my $temp_criterion = q[snps > 10000, average depth >= 2 and freemix < 0.05];

  my $json_without_criterion =
qq {
{
 "avg_depth":1.41,
 "freeLK0":815501.89,
 "freeLK1":815503.15,
 "freemix":0,
 "id_run":"7321",
 "info":{"Check":"npg_qc::autoqc::checks::verify_bam_id","Check_version":"58.0","Verifier":"verifyBamID","Verify_options":" --bam in/7321_7#5.bam --vcf /lustre/scratch110/srpipe/population_snv/Homo_sapiens/1000G_Omni25_genotypes_2141/Standard/1000Genomes/Standard-1000Genomes.vcf.gz --self --ignoreRG --minQ 20 --minAF 0.05 --maxDepth 500 --precise --out /tmp/lew2Twr019/7321_7#5.bam"},
 "number_of_reads":1908387,
 "number_of_snps":1351960,
 "path":"in",
 "position":"7",
 "tag_index":"5"}
};

  my $values_wo_criterion = from_json($json_without_criterion);
  my %values1 = %{$values_wo_criterion};
  my $v1 = \%values1;

  $rs->deflate_unique_key_components($v1);
  lives_ok {$rs->find_or_new($v1)->set_inflated_columns($v1)->update_or_insert()}
    'Check record inserted';
  my $rs1 = $rs->search({});
  is($rs1->count, 1, q[one row created in the table]);
  my $row = $rs1->next;
  is(ref $row->info, 'HASH', 'info returned as hash ref');
  cmp_deeply($row->info, $values_wo_criterion->{'info'},
    'info hash content is correct');
  is($row->criterion,
    q[snps > 10000, average depth >= 4 and freemix < 0.05],
    q[Correct criterion for checks with no criterion in json]);
  $rs1->delete_all;
};

subtest 'Result with criterion in json' => sub {
  plan tests => 5;

  my $temp_criterion = q[snps > 10000, average depth >= 4 and freemix < 0.05];

  my $json_with_criterion =
qq {
{
 "avg_depth":1.41,
 "freeLK0":815501.89,
 "freeLK1":815503.15,
 "freemix":0,
 "id_run":"7321",
 "info":{"Check":"npg_qc::autoqc::checks::verify_bam_id","Check_version":"58.0","Criterion":"$temp_criterion","Verifier":"verifyBamID","Verify_options":" --bam in/7321_7#5.bam --vcf /lustre/scratch110/srpipe/population_snv/Homo_sapiens/1000G_Omni25_genotypes_2141/Standard/1000Genomes/Standard-1000Genomes.vcf.gz --self --ignoreRG --minQ 20 --minAF 0.05 --maxDepth 500 --precise --out /tmp/lew2Twr019/7321_7#5.bam"},
 "number_of_reads":1908387,
 "number_of_snps":1351960,
 "path":"in",
 "position":"7",
 "tag_index":"5"}
};

  my $values_w_criterion = from_json($json_with_criterion);
  my %values1 = %{$values_w_criterion};
  my $v1 = \%values1;

  $rs->deflate_unique_key_components($v1);
  lives_ok {$rs->find_or_new($v1)->set_inflated_columns($v1)->update_or_insert()}
    'Check record inserted';
  my $rs1 = $rs->search({});
  is($rs1->count, 1, q[one row created in the table]);
  my $row = $rs1->next;
  is(ref $row->info, 'HASH', 'info returned as hash ref');
  cmp_deeply($row->info, $values_w_criterion->{'info'},
    'info hash content is correct');
  is($row->criterion,
    $temp_criterion,
    q[Correct criterion for checks with criterion in json]);
  $rs1->delete_all;
};

1;


