package AWS::EC2::ReservedInstance;

use strict;
use warnings;

sub id { shift->{reservedInstancesId} }

sub type { shift->{offeringType} }

sub new { 
	my $class = shift;
	bless shift, $class
}

1
