package SitemapTesters;

use strict;
use warnings;

use Test::More;
use Web::Sitemap;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use Encode qw(decode);

sub _get_test_file_contents {
	my ($name) = @_;

	ok -f $name, "file exists";
	my $contents;
	gunzip $name => \$contents
		or die "gunzip failed: $GunzipError";

	# decode, gunzip does not decode
	$contents = decode('utf-8', $contents);

	# add a newline here because HEREDOCs always include it
	$contents .= "\n";

	return $contents;
}

sub test_file {
	my ($name, $expected) = @_;

	my $contents = _get_test_file_contents($name);
	is $contents, $expected, "file content ok";
}

sub test_big_file {
	my ($name, $expected) = @_;

	my $contents = _get_test_file_contents($name);
	ok $contents eq $expected, "big file content ok";
}

sub new_dies {
	my ($params, $message) = @_;

	local $@;
	my $ret = eval { Web::Sitemap->new(%$params); 1; };
	ok !$ret, $message;
}

1;
