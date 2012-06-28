package AWS::CloudWatch;

use strict;
use warnings;

use base 'AWS';

use POSIX 'strftime';
use XML::Simple;
use Data::Dumper;

use constant VERSION => '2010-08-01';

sub new {
	my $self=shift;
	$self = $self->SUPER::new(@_);
	my %A = @_;
	if(my $r = $A{region}){
		$self->{host} = $self->get_endpoint($r);
	} else {
		$self->{host} = 'monitoring.amazonaws.com'
	}
	$self->{Version} = VERSION;
	$self
}


sub _make_endpoint { 'monitoring.'. $_[1] . '.amazonaws.com' }

sub list_metrics {
	my $self = shift;
	print $self->get_response(
                Action => 'ListMetrics' );
}

sub get_stats {
	my $self = shift;
	my %A = @_;
	$A{ Action } = 'GetMetricStatistics';
	$A{Namespace} ||='AWS/EC2';
	$A{Period} ||=1200;
	my $now = time;
	$A{StartTime} ||= strftime ('%Y-%m-%dT%H:%M:%S', gmtime($now - 1300));
	$A{EndTime} ||= strftime ('%Y-%m-%dT%H:%M:%S', gmtime($now - 100));
	if(my $dimensions = delete $A{dimension}){
		my $i;
		while(my ($x, $y) = each %{$dimensions}){
			my @members = ref $y ? @$y : ($y);
			my $i;
			for (@members){
				$i++;
				$A{"Dimensions.Member.$i.Name"}=$x;
				$A{"Dimensions.Member.$i.Value"}=$_
			}
		}
	}
	if(my $stats = delete $A{statistics}){
		my $i;
		my @stats = ref $stats ? @$stats : ($stats);
		for (@stats){
			$i++;
			$A{"Statistics.Member.$i"} = $_
		}
	} else {
		$A{'Statistics.Member.1'} = 'Average';
	}
	$self->{_xml} = $self->get_response ( %A )
}

sub get_xml { shift->{_xml} }

sub _make_dimensions {
	my %A = @_;
	if(my $instances = delete $A{instances}){
		my %dimensions;
		$dimensions{InstanceId} = [];
		my @instances = ref $instances ? @$instances : ($instances);
		for (@instances){
			push @{$dimensions{InstanceId}}, $_
		}
		$A{dimension} = \%dimensions
	}
	return %A
}

sub _get_NetworkIn {
	my $s = shift;
	my %A = _make_dimensions (@_);
	my $xml_ref = XMLin($s->get_stats( MetricName => 'NetworkIn', %A));
	return $xml_ref->{GetMetricStatisticsResult}->{Datapoints}->{member};
}

sub _get_CPUUtilization {
	my $s = shift;
	my %A = _make_dimensions (@_);
	my $xml_ref = XMLin($s->get_stats( MetricName => 'CPUUtilization', %A));
	return $xml_ref->{GetMetricStatisticsResult}->{Datapoints}->{member};
}

sub get_mean_NetworkIn {
	my $s = shift;
	$s->get_data_with_stat_and_metric(statistics => 'Average', MetricName => 'NetworkIn', @_);
}

sub get_max_CPUUtilization {
	my $s = shift;
	my $ref = $s->_get_CPUUtilization( statistics => 'Maximum', @_);
	('ARRAY' eq ref $ref) ? (reverse map { $_->{Maximum}} @$ref) : ($ref->{Maximum})
}

sub get_formatted_mean_CPUUtilization {
	my $s = shift;
	my @x = $s->get_mean_CPUUtilization(@_);
	my @y = map { sprintf('%0.1f',$_) } @x;
}

sub get_mean_CPUUtilization {
	my $s = shift;
	$s->get_data_with_stat_and_metric(statistics => 'Average', MetricName => 'CPUUtilization', @_);
}

sub get_data_with_stat_and_metric {
	my $s = shift;
	my %A = @_;
	my $stat = $A{statistics};
	my $ref = $s->get_data_with_metric( %A );
	('ARRAY' eq ref $ref) ? (reverse map { $_->{$stat} } @$ref) : ($ref->{$stat})
}

sub get_data_with_metric {
	my $s = shift;
	my %A = _make_dimensions (@_);
	my $xml_ref = XMLin($s->get_stats(%A));
	return $xml_ref->{GetMetricStatisticsResult}->{Datapoints}->{member};
}

1;
