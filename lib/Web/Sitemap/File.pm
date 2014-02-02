package Web::Sitemap::File;

$VERSION = '0.01';

use strict;
use warnings;
use utf8;

use IO::Compress::Gzip qw( $GzipError :flush );

use constant TMP_SUFFIX => '.tmp';

sub new {
	my ($class, $name, %p) = @_;

	my $self = {
		name => $name,
		temp_name => $name. TMP_SUFFIX,
		gzip_buffer => undef,
		compressed_size => 0,
		output_handle => undef
	};
	$self->{gzip_handle} = IO::Compress::Gzip->new(\$self->{gzip_buffer}) or die "GzipError: $GzipError!";
	open $self->{output_handle}, '>', $self->{temp_name} or die "Can't write to file $self->{temp_name}. $!";

	return bless $self, $class;
}

sub append {
	my ($self, $string) = @_;

	utf8::encode($string);
	$self->{gzip_handle}->print($string);
	$self->{gzip_handle}->flush(Z_PARTIAL_FLUSH);

	return $self->_release_buffer;
}

sub _release_buffer {
	my ($self) = @_;

	print { $self->{output_handle} } $self->{gzip_buffer};
	$self->{compressed_size} += length $self->{gzip_buffer};
	undef $self->{gzip_buffer};

	return $self->{compressed_size};
}

sub _already_opened {
	my ($self) = @_;
	return defined $self->{gzip_handle} && not $self->{gzip_handle}->eof;
}

sub close {
	my ($self) = @_;
	if ($self->_already_opened) {
		$self->{gzip_handle}->close;
		$self->_release_buffer;
		close $self->{output_handle};
		unless (rename $self->{temp_name}, $self->{name}) {
			die sprintf("Can't rename '%s' to '%s'", $self->{temp_name}, $self->{name});
		}
	}
}

1;
