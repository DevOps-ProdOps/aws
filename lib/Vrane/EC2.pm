package Vrane::EC2;

=head1 NAME

Vrane::EC2 - A Wrapper around VM::EC2 which control the Amazon EC2 and Eucalyptus Clouds

=head1 SYNOPSIS

 set environment variables EC2_CREDENTIALS which points to the directory containing file 'rest_credentials'

 The file has the following format

        id CAPITALLETTERSNUMBERS
        key mixCaselettersAndNumbers8989


=head1 DESCRIPTION


=head1 CORE METHODS

        Only contain constructor new

=cut

use strict;
use base qw(VM::EC2 AWS::DateTime);


use AWS;

my @extra_regions = ('us-west-2','eu-west-1');

sub new {
	my $class=shift;
	my %args = @_;
	my %credentials;
	if(my $r = $args{region}){
		my $region = $class->new->describe_regions($r);
		push @_,('-endpoint','http://'.$region->regionEndpoint);
	}
	my $aws = AWS->new(@_);
	my $self = $class->SUPER::new(@_,%$aws);
	$self->{_aws} = $aws;
	$self->raise_error(1);
	$self->print_error(1);
	$self
}

my @methods = sort qw(
	blockDeviceMapping
	dnsName
	imageId
	instanceLifecycle
	instanceState
	instanceType
	ipAddress
	kernelId
	keyName
	launchTime
	placement
	privateDnsName
	privateIpAddress
	ramdiskId
	group
);

sub dump_data {
	my $self = shift;
	my $instance = shift;
	for (@methods){
		my $v = $instance->$_;
		next unless $v;
		print "\t",$_,"\t",$v,"\n"
	}
}

sub get_this_instance {
	require VM::EC2::Instance::Metadata;
	my $self = shift;
	return $self->{_this_instance} if $self->{_this_instance};
	my $instance_id = VM::EC2::Instance::Metadata->new->instanceId;
	($self->{_this_instance})= grep { $_->instanceId eq $instance_id } $self->get_all_instances;
	$self->{_this_instance};
}

sub get_all_instances {
	my $self = shift;
	my %args = @_;
	my @instances =@{$self->{_instances} || []};
	if($args{fresh} || !@instances){
		@instances = $self->_get_all_instances;
	} elsif(@instances){
		return @instances;
	}
	$self->{_instances} = \@instances;
	@instances;
}

sub get_all_volumes {
	my $self = shift;
	return $self->_get_objects_from_all_regions('volumes');
}

sub _get_objects_from_all_regions {
	my $self = shift;

	my $objects = shift;
	die "Need objects" unless $objects;
	my $method = 'describe_'.$objects;
	my @objects = $self->$method;
	for my $obj (@objects){
		$obj->{region} = 'us-east-1'
	}

	for my $er (@extra_regions){
		my $ec2= Vrane::EC2->new(region => $er, '-access_key' => $self->{_aws}->get_access_id, '-secret_key' => $self->{_aws}->get_secret_key);
		my @new_objects = $ec2->$method;
		for my $no (@new_objects){
			$no->{region} = $er
		}
		push @objects, @new_objects
	}
	return @objects
}

sub _get_all_instances {
	my $self = shift;
	return $self->_get_objects_from_all_regions('instances');
}

sub describe_instances {
	my $self = shift;
	my @instances = $self->SUPER::describe_instances( @_ );
	@instances
}

sub get_other_instances {
	my $self = shift;
	my $this = $self->get_this_instance;
	grep { $this ne $_ } $self->get_all_instances;
}

my @devices = ('f'..'z');

sub next_available_device {
	my $class = shift;
	my $instance = shift;
	my @my_devices = $instance->blockDeviceMapping;
	shift @my_devices;
	my $number_of_non_root_devices = @my_devices;
	my $new_device = '/dev/sd'. $devices[$number_of_non_root_devices];
	if(grep { $new_device eq $_ } @my_devices){
		warn "expecting device assignment from /dev/sdf in order\n";
		return
	}
	return $new_device;
}

sub set_dns_hostname {
	my $self = shift;
	my %arg = @_;
	$self->{_tiny} ||= TinyDns::DBI->new;
	my $host = $arg{hostname} || die "Need hostname to set DNS hostname";
	my $i = $arg{instance} || die "Need instance object to get ip addresses";
	my %dns = (
		action => 'create_or_replace_hostname',
		hostname => $host,
		ipaddress => [$i->ipAddress, $i->privateIpAddress],
		ttl => [111,111],
		client_location => ['ex','in']
	);
	$self->{_tiny}->request(%dns);
}

sub describe_images {
	my $self = shift;
	my @mine = ('-owner', 'self');
	my %arg = (@mine, @_);
	$self->SUPER::describe_images(%arg)
}

sub describe_snapshots {
	my $self = shift;
	my @mine = ('-owner', 'self');
	my %arg = (@mine, @_);
	$self->SUPER::describe_snapshots(%arg)
}

2;
