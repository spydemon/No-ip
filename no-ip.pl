#!/usr/bin/env perl
use v5.28;

use feature 'signatures';
use strict;
use warnings;

use Config::Tiny;
use Data::Dumper;
use JSON::Tiny('decode_json');
use LWP::Protocol::https;
use REST::Client;

my $CONFIG = Config::Tiny->read('no-ip.cfg')->{_};
$CONFIG->{domain} =~ /\.(.*\..+)$/;
$CONFIG->{zone} = $1;
my $API = REST::Client->new();


sub get_uuid () {
	state $uuid = call_uuid();
	return $uuid;
}

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

say get_uuid();
