#!/usr/bin/env perl
use v5.28;

use feature 'signatures';
use strict;
use warnings;
no warnings 'experimental';

use Config::Tiny;
use Data::Dumper;
use JSON::Tiny('decode_json');
use LWP::Protocol::https;
use REST::Client;

my $CONFIG = Config::Tiny->read('no-ip.cfg')->{_};
$CONFIG->{domain} =~ /^(.*)\.(.*\..+)$/;
$CONFIG->{zone} = $2;
$CONFIG->{sub} = $1;
my $API = REST::Client->new();

my $record_ipv4 = get_record($CONFIG->{sub}, 'A');
my $record_ipv6 = get_record($CONFIG->{sub}, 'AAAA');

say Dumper $record_ipv4;
say Dumper $record_ipv6;

# All queries that starts with get will get a cached value of the wanted attribute.
sub get_uuid () {
	state $uuid = call_uuid();
	return $uuid;
}

sub get_record ($name, $type) {
	state %records;
	return $records{"$name-$type"} //= call_record($name, $type);
}

# All queries that starts with call will do a real call to the web-service.
sub call($query) {
	$API->addHeader('X-Api-Key', $CONFIG->{key});
	my $result =
	  decode_json
	  $API->GET("https://dns.api.gandi.net/api/v5/$query")->responseContent();
	return @{$result};
}

sub call_uuid {
	my @zones = call('zones');
	my $uuid;
	for my $zone (@zones) {
		next unless $zone->{name} eq $CONFIG->{zone};
		$uuid = $zone->{uuid};
	}
	return $uuid;
}

sub call_record($name, $type) {
	my @records = call('zones/' . get_uuid() . '/records');
	for my $record (@records) {
		next unless $record->{'rrset_name'} eq $name;
		next unless $record->{'rrset_type'} eq $type;
		return $record;
	}
}
