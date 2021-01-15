use strict;
use warnings;
use Test::More;
use Web::Sitemap;

new_dies({}, 'empty params dies ok');
new_dies({output_dir => 'asdf', asdf => 1}, 'unknown param dies ok');
new_dies({output_dir => 'asdf', move_from_temp_action => 1}, 'incorrect move action dies ok');

done_testing;

sub new_dies {
	my ($params, $message) = @_;

	local $@;
	my $ret = eval { Web::Sitemap->new(%$params); 1; };
	ok !$ret, $message;
}
