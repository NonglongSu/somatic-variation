#!usr/bin/env perl

use strict;
use warnings;
use Bio::Tools::GFF;
use Getopt::Long;
use Number::Closest;
use List::MoreUtils qw/firstidx/;
use Vcf;

my $gff_file;
my $annotation_file;
my $flanks_file;
my $vcf_file;
my %locations;
my %names;
my $help = 0;
my $counter = 0;
my $grouped = 1;

GetOptions(	'gff|g=s' => \$gff_file,
			'annotation|a=s' => \$annotation_file,
			'flanks|f=s' => \$flanks_file,
			'vcf|v=s' => \$vcf_file,
			'replicates|r=i' => \$grouped,
			'help|h|?' => \$help);

pod2usage(1) if $help;
die "Cannot read $gff_file" unless -r $gff_file;
die "Cannot read $annotation_file" unless -r $annotation_file;
die "Cannot read $flanks_file" unless -r $flanks_file;
die "Cannot read $vcf_file" unless -r $vcf_file;

my %annot;
open(my $annotfh, "<", $annotation_file) or die "$!";
while(<$annotfh>){
	(my $jgi_name, my $go_terms, my $gene_name) = (split("\t"))[1,9,11];
	$go_terms ||= '';
	$gene_name ||= '';
	$annot{$jgi_name} = {'go' => $go_terms, 'name' => $gene_name};
	#print join("\t",$jgi_name, $annot{$jgi_name}), "\n";
	#$counter++;
	#exit if $counter > 10;
}

# print $annot{'Eucgr.A00001'}, "\n";
# exit;

my $gffio = Bio::Tools::GFF->new(-file => $gff_file, -gff_version => 3);
my %cds_locations;
while (my $feature = $gffio->next_feature() ){
	my $feat = $feature-> primary_tag();
	if ($feat eq 'gene' or $feat eq 'CDS'){
		my $chr = $feature -> seq_id();
		if ($feat eq 'gene'){
			$locations{$chr} = {} unless exists $locations{$chr};
			my $name = ($feature -> get_tag_values('Name'))[0];
			$locations{$chr} -> {$feature->start} = $name;
			$locations{$chr} -> {$feature->end} = $name;
		    # print join("\t", $feature-> seq_id(), $feature->start, $feature->end, $name, $annot{$name}->{'name'}) , "\n";
		    # $counter++;
		    # exit if $counter > 10;
		}
		else{
			$cds_locations{$chr} = [] unless exists $cds_locations{$chr};
			push(@{$cds_locations{$chr}},$feature->start);
			push(@{$cds_locations{$chr}},$feature->end);
		}
	}
}

my %locs;
for my $chr (sort keys %locations){
	my @all_locs = sort keys $locations{$chr};
	$cds_locations{$chr} = [sort(@{$cds_locations{$chr}})];
	$locs{$chr} = \@all_locs;
}

my %flanks;
open (my $ffh, "<", $flanks_file) or die $!;
while (<$ffh>){
	chomp;
	(my $id, my $loc, my $flank) = split("\t");
	$flanks{$loc} = $flank;
}
close $ffh or die $!;


my $vcf = Vcf->new(file=>"$vcf_file");
my $vcfheader = $vcf->parse_header();
my @samples = $vcf -> get_samples();
my @sampleindex;
for (my $i = 0; $i < scalar(@samples); $i+=$grouped){
	push(@sampleindex, $vcf->get_column_index($samples[$i]));
}



print join("\t", "snp", 1 .. scalar(@sampleindex), "loc", "gene", "distance", "go_terms", "coding_mut", "substitution") , "\n";

while (my $x = $vcf->next_data_array()){
	my $chr = $$x[0];
	my $location = $$x[1];
	my $coordinate = $chr . ':' . $location;
	my $flank = $flanks{$coordinate};
	next unless $flank;
	my @cds_locs = @{$cds_locations{$chr}};
	my $closefinder = Number::Closest->new(number => $location, numbers => $locs{$chr});
	my $closest = $closefinder -> find;
	my $closestgene = $locations{$chr}->{$closest};
	my $distance = abs($closest - $location);
	my $genename = $annot{$closestgene}->{'name'};
	my $gocat = $annot{$closestgene}->{'go'};
	my $in_CDS;
	my $firstindex = List::MoreUtils::firstidx { $_ > $location } @cds_locs;
	if ($firstindex % 2 == 0){ #if 1st loc after snp is even
		#it's the start of a CDS and so is out of a CDS
		$in_CDS = 0;
	}
	else{#it's in a CDS
		$in_CDS = 1;
	}
	my @muts = map{(split(':',$$x[$_]))[0]} @sampleindex;
	print join("\t", $flank, @muts, $coordinate, $genename, $distance, $gocat, $in_CDS, "-"),"\n"
}


$gffio -> close();
exit;

__END__

1. Sequence of flanking region around variant	x
2. 8 columns, each with a GT of a sample
3. Location on grandis	x
4. Nearest gene in grandis	x
5. Distance to nearest gene in grandis	x
6. GO categories	x
7. Mutation in CDS or not	x
8. AA change if in CDS