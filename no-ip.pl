#!/usr/bin/env perl
use v5.10;

use feature 'signatures';
use strict;
use warnings;
no warnings 'experimental';

use FindBin;
chdir $FindBin::Bin;

use Config::Tiny;
use JSON::Tiny('decode_json', 'encode_json');
use LWP::Protocol::https;
use List::Util;
use Net::Address::IP::Local;
use REST::Client;
use WWW::Curl::Easy;

my $CONFIG = Config::Tiny->read('no-ip.cfg')->{_};
$CONFIG->{domain} =~ /^(.*)\.(.*\..+)$/;
$CONFIG->{zone} = $2;
$CONFIG->{sub} = $1;

# The execution of the script can be aborted depending of the current local ip.
exit unless should_run();

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
	my $content = {
	  'rrset_values' => [ $value ],
	  'rrset_ttl'    => 300,
	};
	if ($value eq '') {
		log_message("Delete $name ($type) since network is unreachable.");
		call('zones/' . get_uuid() . "/records/$name/$type", 'DELETE');
	} else {
		log_message("Update $name ($type) with value: $value.");
		call('zones/' . get_uuid() . "/records/$name/$type", 'PUT', $content);
	}
}

# We call an external website for fetching the current public IP address of our network.
# This subroutine will try to resolve the public IPv4 and IPv6.
sub get_current_ip() {
	my @results;
	for my $current_test (CURL_IPRESOLVE_V4, CURL_IPRESOLVE_V6) {
		my $test_label = ($current_test == CURL_IPRESOLVE_V4)
		  ? 'IPv4'
		  : 'IPv6';
		log_message("Get $test_label endpoint.");
		my $result;
		my $curl = WWW::Curl::Easy->new();
		$curl->setopt(CURLOPT_IPRESOLVE, $current_test);
		$curl->setopt(CURLOPT_URL, $CONFIG->{check});
		$curl->setopt(CURLOPT_WRITEDATA, \$result);
		# This error occurs mainly when the current network is not handling the tested
		# kind of IP. Eg: trying to get the current IPv6 on a network that doesn't
		# support them.
		if ($curl->perform) {
			log_message($curl->errbuf);
			push @results, '';
		} else {
			log_message("Endpoint fetched: $result.");
			chomp $result;
			push @results, $result;
		}
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
	$content = ($type eq 'PUT') ? encode_json($content) : {};
	my $result = $API->$type("$url_root/$query", $content);
	if ($result->responseCode() !~ /^20/) {
		die ('HTTP Error: ' . $result->responseCode() . "\n" . $result->responseContent());
	}
	return decode_json($result->responseContent() || '{}');
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
	printf("%s\n", $message);
}

# We will check if the current local IPv4 respect the "only" regex set in the configuration file.
# If the "only" setting is not set, we considerate that the current local IPv4 address match always the pattern.
sub should_run() {
	unless ($CONFIG->{only}) {
		log_message('Setting "only" is not defined. This script will thus always update your domain IP.');
		return 1;
	}
	my $local_ipv4 = Net::Address::IP::Local->public_ipv4();
	my $pattern = $CONFIG->{only};
	if ($local_ipv4 =~ $pattern) {
		log_message("Current local IPv4 ($local_ipv4) match the \"only\" pattern ($pattern). The domain will be updated.");
		return 1;
	}
	log_message("Current local IPv4 ($local_ipv4) doesn't match the \"only\" ($pattern). The script will be aborted.");
	return 0;
}
