#!/usr/bin/env perl
use v5.28;

use feature 'signatures';
use strict;
use warnings;
no warnings 'experimental';

use Config::Tiny;
use JSON::Tiny('decode_json', 'encode_json');
use LWP::Protocol::https;
use List::Util;
use REST::Client;
use WWW::Curl::Easy;

my $CONFIG = Config::Tiny->read('no-ip.cfg')->{_};
$CONFIG->{domain} =~ /^(.*)\.(.*\..+)$/;
$CONFIG->{zone} = $2;
$CONFIG->{sub} = $1;
my $API = REST::Client->new();
$API->addHeader('X-Api-Key', $CONFIG->{key});
$API->addHeader('Content-Type', 'application/json');

my ($current_ipv4, $current_ipv6) = get_current_ip();
my $recorded_ipv4 = get_record($CONFIG->{sub}, 'A');
my $recorded_ipv6 = get_record($CONFIG->{sub}, 'AAAA');

($current_ipv4 ne $recorded_ipv4)
  ? update_record($CONFIG->{sub}, 'A', $current_ipv4)
  : log_message('IPv4 did not change.');
($current_ipv6 ne $recorded_ipv6)
  ? update_record($CONFIG->{sub}, 'AAAA', $current_ipv6)
  : log_message('IPv6 did not change.');

sub update_record($name, $type, $value) {
	log_message("Update $name ($type) with value: $value.");
	my $content = {
	  'rrset_values' => [ $value ],
	  'rrset_ttl'    => 300,
	};
	call('zones/' . get_uuid() . "/records/$name/$type", 'PUT', $content);
}

# We call an external website for fetching the current public IP address of our network.
# This subroutine will try to resolve the public IPv4 and IPv6.
sub get_current_ip() {
	my @results;
	for my $current_test (CURL_IPRESOLVE_V4, CURL_IPRESOLVE_V6) {
		my $result;
		my $curl = WWW::Curl::Easy->new();
		$curl->setopt(CURLOPT_IPRESOLVE, $current_test);
		$curl->setopt(CURLOPT_URL, $CONFIG->{check});
		$curl->setopt(CURLOPT_WRITEDATA, \$result);
		die ($curl->errbuf) if $curl->perform;
		chomp $result;
		push @results, $result;
	}
	return @results;
}

# All queries that starts with get will get a cached value of the wanted attribute.
sub get_uuid() {
	state $uuid = call_uuid();
	return $uuid;
}

sub get_record($name, $type) {
	state %records;
	return $records{"$name-$type"} //= call_record($name, $type);
}

# Exit point of all request that are done on the Gandi API.
sub call($query, $type = 'GET', $content = {}) {
	my $url_root = 'https://dns.api.gandi.net/api/v5';
	$content = ($type eq 'GET') ? {} : encode_json($content);
	my $result = $API->$type("$url_root/$query", $content);
	if ($result->responseCode() !~ /^20/) {
		die ('HTTP Error: ' . $result->responseCode() . "\n" . $result->responseContent());
	}
	return decode_json $result->responseContent();
}

# All queries that starts with call will fetch the $content from a real call to the web-service.
sub call_uuid {
	my @zones = @{call('zones')};
	my $uuid;
	for my $zone (@zones) {
		next unless $zone->{name} eq $CONFIG->{zone};
		$uuid = $zone->{uuid};
	}
	return $uuid;
}

sub call_record($name, $type) {
	my @records = @{call('zones/' . get_uuid() . '/records')};
	for my $record (@records) {
		next unless $record->{'rrset_name'} eq $name;
		next unless $record->{'rrset_type'} eq $type;
		return $record->{'rrset_values'}[0];
	}
}

# Manage logging system.
sub log_message($message) {
	my $date = localtime;
	printf("%s: %s\n", $date, $message);
}
