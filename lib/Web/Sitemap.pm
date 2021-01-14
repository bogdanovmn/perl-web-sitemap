package Web::Sitemap;

our $VERSION = '0.902';

use strict;
use warnings;
use bytes;

use File::Temp;
use File::Copy;
use IO::Compress::Gzip qw/gzip $GzipError/;
use Encode;
use Carp;

use Web::Sitemap::Url;

use constant {
	URL_LIMIT           => 50000,
	FILE_SIZE_LIMIT     => 50 * 1024 * 1024,
	FILE_SIZE_LIMIT_MIN => 1024 * 1024,

	DEFAULT_FILE_PREFIX => 'sitemap.',
	DEFAULT_TAG         => 'tag',
	DEFAULT_INDEX_NAME  => 'sitemap',

	XML_HEAD             => '<?xml version="1.0" encoding="UTF-8"?>',
	XML_MAIN_NAMESPACE   => 'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
	XML_MOBILE_NAMESPACE => 'xmlns:mobile="http://www.google.com/schemas/sitemap-mobile/1.0"',
	XML_IMAGES_NAMESPACE => 'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"'

};


sub new {
	my ($class, %p) = @_;

	my %allowed_keys = map { $_ => 1 } qw(
		output_dir      temp_dir              loc_prefix
		url_limit       file_size_limit       file_prefix
		file_loc_prefix default_tag           index_name
		mobile          images                namespace
		charset         move_from_temp_action
	);

	my @bad_keys = grep { !exists $allowed_keys{$_} } keys %p;
	croak "Unknown parameters: @bad_keys" if @bad_keys;

	my $self = {
		loc_prefix      => '',
		tags            => {},

		url_limit       => URL_LIMIT,
		file_size_limit => FILE_SIZE_LIMIT,
		file_prefix     => DEFAULT_FILE_PREFIX,
		file_loc_prefix => '',
		default_tag     => DEFAULT_TAG,
		index_name      => DEFAULT_INDEX_NAME,
		mobile          => 0,
		images          => 0,
		charset         => 'utf8',

		%p, # actual input values
	};

	$self->{file_loc_prefix} ||= $self->{loc_prefix};

	if ($self->{file_size_limit} < FILE_SIZE_LIMIT_MIN) {
		$self->{file_size_limit} = FILE_SIZE_LIMIT_MIN;
	}

	if ($self->{namespace}) {

		$self->{namespace} = [ $self->{namespace} ]
			if !ref $self->{namespace};

		croak 'namespace must be scalar or array ref!'
			if ref $self->{namespace} ne 'ARRAY';
	}

	unless ($self->{output_dir}) {
		croak 'output_dir expected!';
	}

	if ($self->{temp_dir} and not -w $self->{temp_dir}) {
		croak sprintf "Can't write to temp_dir '%s' (error: %s)", $self->{temp_dir}, $!;
	}

	if ($self->{move_from_temp_action} and ref $self->{move_from_temp_action} ne 'CODE') {
		croak 'move_from_temp_action must be code ref!';
	}

	return bless $self, $class;
}

sub add {
	my ($self, $url_list, %p) = @_;

	my $tag = $p{tag} || $self->{tag};

	if (ref $url_list ne 'ARRAY') {
		croak 'The list of sitemap URLs must be array ref';
	}

	for my $url (@$url_list) {
		my $data = Web::Sitemap::Url->new(
			$url,
			mobile     => $self->{mobile},
			loc_prefix => $self->{loc_prefix},
		)->to_xml_string;

		if ($self->_file_limit_near($tag, bytes::length $data)) {
			$self->_next_file($tag);
		}

		$self->_append_url($tag, $data);
	}
}

sub finish {
	my ($self, %p) = @_;

	return unless keys %{$self->{tags}};

	my $index_temp_file_name = $self->_temp_file->filename;
	open my $index_file, '>' . $index_temp_file_name or croak "Can't open file '$index_temp_file_name'! $!\n";

	print  {$index_file} XML_HEAD;
	printf {$index_file} "\n<sitemapindex %s>", XML_MAIN_NAMESPACE;

	for my $tag (sort keys %{$self->{tags}}) {
		my $data = $self->{tags}{$tag};

		$self->_close_file($tag);
		for my $page (1 .. $data->{page}) {
			printf {$index_file} "\n<sitemap><loc>%s/%s</loc></sitemap>", $self->{file_loc_prefix}, $self->_file_name($tag, $page);
		}
	}

	print {$index_file} "\n</sitemapindex>";
	close $index_file;

	$self->_move_from_temp(
		$index_temp_file_name,
		$self->{output_dir}. '/'. $self->{index_name}. '.xml'
	);
}

sub _move_from_temp {
	my ($self, $temp_file_name, $public_file_name) = @_;

	#printf "move %s -> %s\n", $temp_file_name, $public_file_name;

	if ($self->{move_from_temp_action}) {
		$self->{move_from_temp_action}($temp_file_name, $public_file_name);
	}
	else {
		File::Copy::move($temp_file_name, $public_file_name)
			or croak sprintf 'move %s -> %s error: %s', $temp_file_name, $public_file_name, $!;
	}
}

sub _file_limit_near {
	my ($self, $tag, $new_portion_size) = @_;

	return 0 unless defined $self->{tags}{$tag};

	# printf("tag: %s.%d; url: %d; gzip_size: %d (%d)\n",
	# 	$tag,
	# 	$self->{tags}->{$tag}->{page},
	# 	$self->{tags}->{$tag}->{url_count},
	# 	$self->{tags}->{$tag}->{file_size},
	# 	$self->{file_size_limit}
	# );

	return (
		$self->{tags}{$tag}{url_count} >= $self->{url_limit}
		||
		# 200 bytes should be well enough for the closing tags at the end of the file
		($self->{tags}{$tag}{file_size} + $new_portion_size) >= ($self->{file_size_limit} - 200)
	);
}

sub _temp_file {
	my ($self) = @_;

	return File::Temp->new(
		UNLINK => 1,
		$self->{temp_dir} ? ( DIR => $self->{temp_dir} ) : ()
	);
}

sub _set_new_file {
	my ($self, $tag) = @_;

	my $temp_file = $self->_temp_file;

	$self->{tags}{$tag}{page}++;
	$self->{tags}{$tag}{url_count} = 0;
	$self->{tags}{$tag}{file_size} = 0;
	$self->{tags}{$tag}{file} = IO::Compress::Gzip->new($temp_file->filename)
		or croak "gzip failed: $GzipError\n";
	$self->{tags}{$tag}{file}->autoflush;
	$self->{tags}{$tag}{temp_file} = $temp_file;

	# Do not check the file for oversize because it is empty and will likely
	# not exceed 1MB with initial tags alone

	my @namespaces = (XML_MAIN_NAMESPACE);
	push @namespaces, XML_MOBILE_NAMESPACE
		if $self->{mobile};
	push @namespaces, XML_IMAGES_NAMESPACE
		if $self->{images};
	push @namespaces, @{$self->{namespace}}
		if $self->{namespace};

	$self->_append(
		$tag,
		sprintf("%s\n<urlset %s>", XML_HEAD, join(' ', @namespaces))
	);
}

sub _file_handle {
	my ($self, $tag) = @_;

	unless (exists $self->{tags}{$tag}) {
		$self->_set_new_file($tag);
	}

	return $self->{tags}{$tag}{file};
}

sub _append {
	my ($self, $tag, $data) = @_;

	$self->_file_handle($tag)->print(Encode::encode($self->{charset}, $data));
	$self->{tags}{$tag}{file_size} += bytes::length $data;
}

sub _append_url {
	my ($self, $tag, $data) = @_;

	$self->_append($tag, $data);
	$self->{tags}{$tag}{url_count}++;
}

sub _next_file {
	my ($self, $tag) = @_;

	$self->_close_file($tag);
	$self->_set_new_file($tag);
}

sub _close_file {
	my ($self, $tag) = @_;

	$self->_append($tag, "\n</urlset>");
	$self->_file_handle($tag)->close;

	$self->_move_from_temp(
		$self->{tags}{$tag}{temp_file}->filename,
		$self->{output_dir}. '/'. $self->_file_name($tag)
	);
}

sub _file_name {
	my ($self, $tag, $page) = @_;
	return
		$self->{file_prefix}
		. $tag
		. '.'
		. ($page || $self->{tags}{$tag}{page})
		. '.xml.gz'
	;
}

1;

__END__

=head1 NAME

Web::Sitemap - Simple way to generate sitemap files with paging support

=head1 SYNOPSIS

Each instance of the class Web::Sitemap is manage of one index file.
Now it always use Gzip compress.

	use Web::Sitemap;

	my $sm = Web::Sitemap->new(
	output_dir => '/path/for/sitemap',

	### Options ###

	temp_dir    => '/path/to/tmp',
	loc_prefix  => 'http://my_doamin.com',
	index_name  => 'sitemap',
	file_prefix => 'sitemap.',

	# mark for grouping urls
	default_tag => 'my_tag',


	# add <mobile:mobile/> inside <url>, and appropriate namespace (Google standard)
	mobile      => 1,

	# add appropriate namespace (Google standard)
	images      => 1,

	# additional namespaces (scalar or array ref) for <urlset>
	namespace   => 'xmlns:some_namespace_name="..."',

	# location prefix for files-parts of the sitemap (default is loc_prefix value)
	file_loc_prefix  => 'http://my_doamin.com',

	# specify data input charset
	charset => 'utf8',

	move_from_temp_action => sub {
		my ($temp_file_name, $public_file_name) = @_;

		# ...some action...
		#
		# default behavior is
		# File::Copy::move($temp_file_name, $public_file_name);
	}

	);

	$sm->add(\@url_list);


	# When adding a new portion of URL, you can specify a label for the file in which these will be URL

	$sm->add(\@url_list1, tag => 'articles');
	$sm->add(\@url_list2, tag => 'users');


	# If in the process of filling the file number of URL's will exceed the limit of 50 000 URL or the file size is larger than 10MB, the file will be rotate

	$sm->add(\@url_list3, tag => 'articles');


	# After calling finish() method will create an index file, which will link to files with URL's

	$sm->finish;

=head1 DESCRIPTION

Also support for Google images format:

	my @img_urls = (

		# Foramt 1
		{
			loc => 'http://test1.ru/',
			images => {
				caption_format => sub {
					my ($iterator_value) = @_;
					return sprintf('Vasya - foto %d', $iterator_value);
				},
				loc_list => [
					'http://img1.ru/',
					'http://img2.ru'
				]
			}
		},

		# Foramt 2
		{
			loc => 'http://test11.ru/',
			images => {
				caption_format_simple => 'Vasya - foto',
				loc_list => ['http://img11.ru/', 'http://img21.ru']
			}
		},

		# Format 3
		{
			loc => 'http://test122.ru/',
			images => {
				loc_list => [
					{ loc => 'http://img122.ru/', caption => 'image #1' },
					{ loc => 'http://img133.ru/', caption => 'image #2' },
					{ loc => 'http://img144.ru/', caption => 'image #3' },
					{ loc => 'http://img222.ru', caption => 'image #4' }
				]
			}
		}
	);


	# Result:

	<?xml version="1.0" encoding="UTF-8"?>
	<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
	<url>
		<loc>http://test1.ru/</loc>
		<image:image>
			<loc>http://img1.ru/</loc>
			<caption><![CDATA[Vasya - foto 1]]></caption>
		</image:image>
		<image:image>
			<loc>http://img2.ru</loc>
			<caption><![CDATA[Vasya - foto 2]]></caption>
		</image:image>
	</url>
	<url>
		<loc>http://test11.ru/</loc>
		<image:image>
			<loc>http://img11.ru/</loc>
			<caption><![CDATA[Vasya - foto 1]]></caption>
		</image:image>
		<image:image>
			<loc>http://img21.ru</loc>
			<caption><![CDATA[Vasya - foto 2]]></caption>
		</image:image>
	</url>
	<url>
		<loc>http://test122.ru/</loc>
		<image:image>
			<loc>http://img122.ru/</loc>
			<caption><![CDATA[image #1]]></caption>
		</image:image>
		<image:image>
			<loc>http://img133.ru/</loc>
			<caption><![CDATA[image #2]]></caption>
		</image:image>
		<image:image>
			<loc>http://img144.ru/</loc>
			<caption><![CDATA[image #3]]></caption>
		</image:image>
		<image:image>
			<loc>http://img222.ru</loc>
			<caption><![CDATA[image #4]]></caption>
		</image:image>
	</url>
	</urlset>

=head1 AUTHOR

Mikhail N Bogdanov C<< <mbogdanov at cpan.org > >>

=cut

