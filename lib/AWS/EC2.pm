package AWS::EC2;

use strict;
use warnings;

use base 'AWS';
use XML::Simple 'XMLin';
use Carp;

my %region = (
	virginia => 'us-east-1',
	oregon   => 'us-west-2'
);

use constant VERSION => '2011-12-15';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new( host => 'ec2.us-east-1.amazonaws.com' , Version => VERSION );
	my %args = @_;
	if($args{region} || $args{'region-name'}){
		$self->{host} = $self->get_endpoint(%args);
		$self->{'_region-name'}= $args{'region-name'} || $region{ $args{region} }
	}
	$self
}

sub get_endpoint {
	my $self = shift;
	my %args = @_;
	my $region = delete $args{'region-name'};
	$region ||= $region{ $args{region} };
	my $ref = XMLin ($self->get_response( Action => 'DescribeRegions', 'RegionName.1' => $region ));
	$ref->{regionInfo}->{item}->{regionEndpoint}
}

sub describe_reserved_instances {
	my $self = shift;
	my $ref = XMLin $self->get_response(Action => 'DescribeReservedInstances', @_);
	$ref->{reservedInstancesSet}->{item}
}

sub revoke_incoming {
	my $self = shift;
	my $ref = XMLin $self->get_response( Action => 'RevokeSecurityGroupIngress', @_);
	$ref->{Errors} ? $ref : 1
}

sub AUTOLOAD {
	my $self = shift;
	my $sub = our $AUTOLOAD;
	$sub =~ s/.*:://;
	print $self->SUPER::get_response(Action => $sub , @_);
}

sub DESTROY {}

sub _get_all_reserved_instances {
	my $self = shift;
	my $all = $self->describe_reserved_instances;
	my $current_region = $self->{'_region-name'} || 'us-east-1';
	my @region_names = grep { $current_region ne $_ } values %region;
	for my $rn (@region_names){
		my $ec2 = AWS::EC2->new( 'region-name' => $rn);
		push @$all, @{$ec2->describe_reserved_instances}
	}
	$self->{_reserved_instances_from_all_regions} = $all
}

sub _validate_vm_object {
	my $vm = shift;
	unless(ref $vm && $vm->can('instanceType') && $vm->can('placement') && $vm->can('instanceId')){
		my $ref = ref $vm;
		die "This object type reference '$ref' is not suitable $vm\n"
	}
}

sub is_running_reserved {
	my $self = shift;
	my $vm = shift;
	$self->{_reserved_instances_from_all_regions} || $self->_get_all_reserved_instances;
	_validate_vm_object($vm);
	my $i = 0;
	for my $rn (@{$self->{_reserved_instances_from_all_regions}}){
		if($rn->{instanceType} eq $vm->instanceType && $rn->{availabilityZone} eq $vm->placement &&
			!exists $self->{_reserved_instances_from_all_regions}->[$i]->{checked} &&
			$rn->{state} eq 'active' && $rn->{offeringType} ne 'Light Utilization'){
			$self->{_reserved_instances_from_all_regions}->[$i]->{checked} = 1;
			$self->{_reserved_running}->{$vm->placement}->{$vm->instanceId} = $rn;
			return AWS::EC2::ReservedInstance->new($rn)
		}	
		$i++
	}
	undef	
}

sub get_instances_running_as_unreserved {
	my $self = shift;
	$self->{_reserved_instances_from_all_regions} || $self->_get_all_reserved_instances;
	map { $_->{reservedInstancesId} => $_ } grep { !exists $_->{checked} && $_->{state} eq 'active' } @{ $self->{_reserved_instances_from_all_regions} };	
}

sub get_reserved_hourly_charge {
	my $self = shift;
	my $vm = shift;
	_validate_vm_object($vm);
	my $az = $vm->placement;
	my $id = $vm->instanceId;
	$self->{_reserved_running}->{$az}->{$id}->{recurringCharges}->{item}->{amount} || $self->{_reserved_running}->{$az}->{$id}->{usagePrice}
}

1
