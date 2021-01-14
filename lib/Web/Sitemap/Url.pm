package Web::Sitemap::Url;

our $VERSION = '0.012';

use strict;
use warnings;
use utf8;

use Carp;

sub new {
	my ($class, $data, %p) = @_;

	my %allowed_keys = map { $_ => 1 } qw(
		mobile loc_prefix
	);

	my @bad_keys = grep { !exists $allowed_keys{$_} } keys %p;
	croak "Unknown parameters: @bad_keys" if @bad_keys;

	my $self = {
		mobile     => 0,
		loc_prefix => '',
		%p, # actual input values
	};

	if (not ref $data) {
		$self->{loc} = $data;
	}
	elsif (ref $data eq 'HASH') {
		unless (defined $data->{loc}) {
			croak 'Web::Sitemap::Url first argument hash must have `loc` key defined';
		}
		$self = { %$self, %$data };
	}
	else {
		croak 'Web::Sitemap::Url first argument must be a plain scalar or a hash reference';
	}

	return bless $self, $class;
}

sub to_xml_string {
	my ($self, %p) = @_;

	return sprintf(
		"\n<url><loc>%s%s</loc>%s%s%s</url>",
			$self->{loc_prefix},
			$self->{loc},
			$self->{changefreq} ? sprintf('<changefreq>%s</changefreq>', $self->{changefreq}) : '',
			$self->{mobile}     ? '<mobile:mobile/>' : '',
			$self->_images_xml_string
	);
}

sub _images_xml_string {
	my ($self) = @_;

	my $result = '';

	if (defined $self->{images}) {
		my $i = 1;
		for my $image (@{$self->{images}{loc_list}}) {
			my $loc = ref $image eq 'HASH' ? $image->{loc} : $image;

			my $caption = '';
			if (ref $image eq 'HASH' and defined $image->{caption}) {
				$caption = $image->{caption};
			}
			elsif (defined $self->{images}{caption_format_simple}) {
				$caption = $self->{images}{caption_format_simple}. " $i";
			}
			elsif (defined $self->{images}{caption_format}) {
				$caption = &{$self->{images}{caption_format}}($i);
			}

			$result .= sprintf(
				"\n<image:image><loc>%s</loc><caption><![CDATA[%s]]></caption></image:image>",
				$loc, $caption
			);

			$i++;
		}
	}

	return $result;
}

1
