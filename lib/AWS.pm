package AWS;

=head1 NAME

AWS - A base class for all AWS other modules

=head1 SYNOPSIS

	my $aws = AWS->new;
	my $access_id = $aws->get_access_id;
	my $secret_key = $aws->get_secret_key;

	This assumes you have set environment variables EC2_CREDENTIALS which points to
	the directory containing file 'rest_credentials'. 

	Alternatively if your home directory contains '.ec2' directory with the file
	'rest_credentials' the credentials will be pulled from that file.  
	Permission on this directory and file must be sane.

	The file has the following format

		AWSAccessKeyId=CAPITALLETTERSNUMBERS
		AWSSecretKey=mixCaselettersAndNumbers8989

	No leading/trailing spaces.  
	This is the same format used by AWS_CREDENTIAL_FILE as specified in AWS/IAM documentation

	Then you can do

		$aws->get_response( host => 'some.fqdn.aws.com',\%param);

	This method will construct the proper LWP request and return you the response from AWS.

	The purpose of this module is
		1. to retrieve AWS credentials in a consistent manner
		2. to abstract the low level working AWS Rest API from the other modules

=head1 DESCRIPTION


=head1 CORE METHODS

        Constructor new can be called with no argument and will try its best to parse rest credentials
	It can also be called with credentials in the argument list; the format for passing the credentials follows that of VM::EC2 with a hash with keys '-access_key' and '-secret_key'

	Constructor get_response takes as argument a hash with following key
	'host' e.g. monitoring.aws.com
	'method' e.g. POST
	and hash containing query parameters
=cut

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request::Common 'POST';

use MIME::Base64 'encode_base64';
use URI::Escape 'uri_escape';
use POSIX 'strftime';
use File::Basename 'dirname';

my %region_name = (
	oregon   => 'us-west-2',
	virginia => 'us-west-1'
);

sub new {
	my $class=shift;
	my %args = @_;
	my %credentials;
	unless($args{-access_key} && $args{-secret_key}){
		if(my $file_path = $ENV{AWS_CREDENTIAL_FILE}){
			my $credentials_dir = dirname($file_path);
			if(_security_ok($credentials_dir) && _security_ok($file_path)){
				my %credentials = _get_access_and_keys($file_path);
				if(%credentials){ push @_, %credentials }
			} 
		} else { warn "No credential supplied or AWS_CREDENTIAL_FILE environment set" }
	}
	bless { @_ }, $class
}

sub _security_ok {
	my $file = shift;
	unless(-e $file){
		warn "$file does not exist\n";
		return
	}
	unless(-O $file){
		warn "$file has bad ownership\n";
		return;
	}
	if(-d $file){
		return unless _permission_ok($file.'/..');
	}
	_permission_ok($file);
}

sub get_endpoint {
	my $self = shift;
	my $region = shift;
	if ($region =~ /-\d$/){
		return $self->_make_endpoint ($region)
	}
	my $region_name = $region_name{$region};
	die "Cannot determine endpoint from region $region" unless $region_name;
	$self->_make_endpoint($region_name)
}

sub _permission_ok {
	my $path = shift;
	my $mode = (stat($path))[2];
	my $permission = sprintf "%04o",$mode & 07777;
	return 1 if $permission =~ /^0[4-7]00$/;
	warn "Bad permission $permission on $path\n";
	0	
}

sub _get_access_and_keys {
	my $file = shift;
	if(open my $J, '<', $file){
		my %data;
		while(<$J>){
			if(!$data{-access_key} && /^AWSAccessKeyId=([A-Z0-9]+)/){
				$data{-access_key} = $1;
				last if $data{-secret_key};
				next
			}
			if(!$data{-secret_key} && m|^AWSSecretKey=([\w+/]+)|){
				$data{-secret_key} = $1;
				last if $data{-access_key}
			}
		}
		close $J or die "Cannot close file $file\n";
		unless($data{-secret_key} && $data{-access_key}){
			warn "no credentials found in the file\n";
			return;
		}
		return %data
	} else { warn "Cannot open file $file\n" }
}

sub get_secret_key { shift->{'-secret_key'} }

sub get_access_id { shift->{'-access_key'} }

sub _get_signature {
	my $self = shift;
}

sub _get_browser {
	my $self = shift;
	return $self->{_browser} if $self->{_browser};
	$self->{_browser} = LWP::UserAgent->new;
}

sub _uri_escape {
	uri_escape(shift,'^\w\-.~');
}

sub get_response {
	require Digest::HMAC_SHA1;

	my $self = shift;
	my %B = @_;
	my $ua = $self->_get_browser;
	my $host = delete $B{host};
	$host ||= $self->{host};
	my $uri = delete $B{uri};
	$uri ||= '/';
	my %A = (
		SignatureVersion=> 2,
		SignatureMethod => 'HmacSHA1',
		AWSAccessKeyId  => $self->{'-access_key'},
	);
	my $string = "POST\n$host\n$uri\n";
	$B{Version} ||= $self->{Version};
	$B{Timestamp} ||= strftime ('%Y-%m-%dT%H:%M:%S', gmtime);
	%A = (%A, %B);
	$string .= join '&', map { _uri_escape($_) . '=' . _uri_escape($A{$_}) } sort keys %A;
	my $key = $self->{'-secret_key'};
	my $digest = Digest::HMAC_SHA1::hmac_sha1($string, $key);
	$A{Signature}=encode_base64($digest,'');
	my $response = $ua->request(POST('https://'. $host, ,\%A));
	$response->content
}

1;
