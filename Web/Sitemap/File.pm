package Web::Sitemap::File;

use strict;
use warnings;
use utf8;

use IO::Compress::Gzip qw( $GzipError );

use constant TMP_SUFFIX => '.tmp';

sub new {
	my ($class, $name, %p) = @_;

	my $self = {
		name => $name,
		temp_name => $name. TMP_SUFFIX
	};
	$self->{handle} = IO::Compress::Gzip->new($self->{temp_name}) or die "GzipError: $GzipError!";

	return bless $self, $class;
}

sub append {
	my ($self, $string) = @_;
	$self->{handle}->print($string);
}

sub _already_opened {
	my ($self) = @_;
	return defined $self->{handle} && not $self->{handle}->eof;
}

sub close {
	my ($self) = @_;
	if ($self->_already_opened) {
		$self->{handle}->close;
		unless (rename $self->{temp_name}, $self->{name}) {
			die sprintf("Can't rename '%s' to '%s'", $self->{temp_name}, $self->{name});
		}
	}
}

1;
