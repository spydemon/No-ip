#!/usr/bin/env perl
use v5.28;

use feature 'signatures';
use strict;
use warnings;
no warnings 'experimental';

use Config::Tiny;
use Data::Dumper;
use JSON::Tiny('decode_json', 'encode_json');
use LWP::Protocol::https;
use List::Util;
use REST::Client;

my $CONFIG = Config::Tiny->read('no-ip.cfg')->{_};
$CONFIG->{domain} =~ /^(.*)\.(.*\..+)$/;
$CONFIG->{zone} = $2;
$CONFIG->{sub} = $1;
my $API = REST::Client->new();
$API->addHeader('X-Api-Key', $CONFIG->{key});
$API->addHeader('Content-Type', 'application/json');

my $record_ipv4 = get_record($CONFIG->{sub}, 'A');
my $record_ipv6 = get_record($CONFIG->{sub}, 'AAAA');

update_record($CONFIG->{sub}, 'A', '1.2.6.7');

sub update_record($name, $type, $value) {
	my $content = {
	  'items' => [{
	    'rrset_values' => [ $value ],
	    'rrset_ttl'    => 300,
	    'rrset_type'    => $type,
	  }]
	};
	call('zones/' . get_uuid() . "/records/$name", 'PUT', $content);
}

# All queries that starts with get will get a cached value of the wanted attribute.
sub get_uuid () {
	state $uuid = call_uuid();
	return $uuid;
}

sub get_record($name, $type) {
	state %records;
	return $records{"$name-$type"} //= call_record($name, $type);
}

# All queries that starts with call wil, $contentl do a real call to the web-service.
sub call($query, $type = 'GET', $content = undef) {
	no strict 'refs';
	my $url_root = 'https://dns.api.gandi.net/api/v5';
	my $result;
	if ($type eq 'GET') {
	  $result = decode_json
	    $API->GET("$url_root/$query")->responseContent();
	} elsif ($type eq 'POST') {
	  $content = encode_json($content);
	  $result = $API->POST("$url_root/$query", $content)->responseContent();
	} elsif ($type eq 'DELETE') {
	  $result = $API->DELETE("$url_root/$query")->responseContent();
	} elsif ($type eq 'PUT') {
		$content = encode_json($content);
		$result = $API->PUT("$url_root/$query", $content)->responseContent();
	} else {
	  ...
	}
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
