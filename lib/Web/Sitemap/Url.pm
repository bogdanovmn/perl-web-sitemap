package Web::Sitemap::Url;

use strict;
use warnings;
use utf8;


sub new {
	my ($class, $data) = @_;
	
	if (not ref $data) {
		return bless { loc => $data }, $class;
	}
	elsif (ref $data eq 'HASH') {
		unless (defined $data->{loc}) {
			die 'SITEMAP::URL->new($data): not defined $data->{loc}';
		}
		return bless { %$data }, $class;
	}
	else {
		die 'SITEMAP::URL->new($data): $data must be scalar or hash ref';
	}
}

sub to_xml_string {
	my ($self) = @_;
	return sprintf('<url><loc>%s</loc>%s</url>', $self->{loc}, $self->_images_xml_string);
}

sub _images_xml_string {
	my ($self) = @_;
	
	my $result = '';

	return $result unless defined $self->{images};

	my $i = 1;
	for my $image (@{$self->{images}->{loc_list}}) {
		my $loc = ref $image eq 'HASH' ? $image->{loc} : $image;
		
		my $caption = '';
		if (ref $image eq 'HASH' && defined $image->{caption}) {
			$caption = $image->{caption};
		}
		elsif (defined $self->{images}->{caption_format_simple}) {
			$caption = $self->{images}->{caption_format_simple}. " $i";
		}
		elsif (defined $self->{images}->{caption_format}) {
			$caption = &{$self->{images}->{caption_format}}($i);
		}

		$result .= sprintf(
			"\n<image:image><loc>%s</loc><caption><![CDATA[%s]]></caption></image:image>",
			$loc, $caption
		);
		$i++;
	}
	return $result;
}

1
