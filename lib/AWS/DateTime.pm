package AWS::DateTime;

use strict;
use POSIX 'strftime';

my $now;


sub set_now {
	my $class = shift;
	my $_now = shift;
	$now = $_now;
	$now ||= time
}

sub get_now {
	my $class = shift;
	my $_now = $now;
	$_now ||= $class->set_now();
	_generic($_now)
}

sub _generic { strftime ('%Y-%m-%dT%H:%M:%S', gmtime(shift) ) }

sub hours_ago {
	my $class = shift;
	$class->seconds_in_future(-1 * 3600 * shift);
}

sub seconds_in_future {
	my $class = shift;
	$class->set_now(time + shift);
	_generic($now)
}

2;	
