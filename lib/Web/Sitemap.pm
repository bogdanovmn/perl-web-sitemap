package Web::Sitemap;

our $VERSION = '0.04';

=head1 NAME
 
 Web::Sitemap - Simple way to generate sitemap files with paging support.

=cut

=head1 SYNOPSIS
 
 Each instance of the class Web::Sitemap is manage of one index file.
 Now it always use Gzip compress.


 use Web::Sitemap;
 
 my $sm = Web::Sitemap->new(
	output_dir => '/path/for/sitemap',
	
	# Options

	loc_prefix => 'http://my_doamin.com',
	prefix => 'sitemap.',
	default_tag => 'my_tag',
	index_name => 'sitemap.xml'
 );

 $sm->add(\@url_list);
 

 # When adding a new portion of URL, you can specify a label for the file in which these will be URL
 
 $sm->add(\@url_list1, {tag => 'articles'});
 $sm->add(\@url_list2, {tag => 'users'});
 

 # If in the process of filling the file number of URL's will exceed the limit of 50 000 URL or the file size is larger than 10MB, the file will be rotate

 $sm->add(\@url_list3, {tag => 'articles'});

 
 # After calling finish() method will create an index file, which will link to files with URL's

 $sm->finish;

=cut

use strict;
use warnings;
use utf8;

use Web::Sitemap::Url;
use Web::Sitemap::File;

use constant {
	URL_LIMIT => 50000,
	FILE_SIZE_LIMIT => 10*1024*1024,
	FILE_SIZE_LIMIT_MIN => 1024*1024,
	
	DEFAULT_PREFIX => 'sitemap.',
	DEFAULT_TAG => 'tag',
	DEFAULT_INDEX_NAME => 'sitemap.xml',

	XML_HEAD => '<?xml version="1.0" encoding="UTF-8"?>',
	XML_MAIN_NAMESPACE => 'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'
};


sub new {
	my ($class, %p) = @_;

	my $self = {
		output_dir => $p{output_dir},
		loc_prefix => $p{loc_prefix} || '',
		tags => {},
		gzip => $p{gzip} || 1,
		url_limit => $p{url_limit} || URL_LIMIT,
		file_size_limit => $p{file_size_limit} || FILE_SIZE_LIMIT,
		prefix => $p{prefix} || DEFAULT_PREFIX,
		default_tag => $p{default_tag} || DEFAULT_TAG,
		index_name => $p{index_name} || DEFAULT_INDEX_NAME
	};

	if ($self->{file_size_limit} < FILE_SIZE_LIMIT_MIN) {
		$self->{file_size_limit} = FILE_SIZE_LIMIT_MIN;
	}

	unless (-w $self->{output_dir}) {
		die "Can't write to output_dir: ". $self->{output_dir};
	}

	return bless $self, $class;
}

sub add {
	my ($self, $url_list, %p) = @_;
	my $tag = $p{tag} || DEFAULT_TAG;

	unless (ref $url_list eq 'ARRAY') {
		die 'Web::Sitemap::add($url_list): $url_list must be array ref';
	}

	for my $url (@$url_list) {
		if ($self->_file_limit_near($tag)) {
			$self->_next_file($tag);
		}
		my $fh = $self->_file_handle($tag);
		my $data = Web::Sitemap::Url->new($url)->to_xml_string;
		$fh->append($data);
		$self->{tags}->{$tag}->{file_size} += length $data;
		$self->{tags}->{$tag}->{url_count}++;
	}
}

sub finish {
	my ($self, %p) = @_;

	return unless keys %{$self->{tags}};

	open INDEX_FILE, '>'. $self->{output_dir}. '/'. $self->{index_name} or die "Can't open file! $!\n";

	print INDEX_FILE XML_HEAD;
	printf INDEX_FILE "\n<sitemapindex %s>\n", XML_MAIN_NAMESPACE;
	while (my ($tag, $data) = each %{$self->{tags}}) {
		$self->_close_file($tag);
		for my $page (1..$data->{page}) {
			printf INDEX_FILE "<sitemap><loc>%s%s</loc></sitemap>\n", $self->{loc_prefix}, $self->_file_name($tag, $page);
		}
	}
	print INDEX_FILE "</sitemapindex>";
	close INDEX_FILE;
}

sub _file_limit_near {
	my ($self, $tag) = @_;

	return 0 unless defined $self->{tags}->{$tag};

	#printf("tag: %s.%d; url: %d; gzip_size: %d (%d)\n",
	#	$tag,
	#	$self->{tags}->{$tag}->{page},
	#	$self->{tags}->{$tag}->{url_count},
	#	$self->{tags}->{$tag}->{file_size},
	#	$self->{file_size_limit}
	#);

	return (
		$self->{tags}->{$tag}->{url_count} >= $self->{url_limit}
		||
		$self->{tags}->{$tag}->{file_size} >= $self->{file_size_limit}
	);
}

sub _set_new_file {
	my ($self, $tag) = @_;
	$self->{tags}->{$tag}->{file} = Web::Sitemap::File->new($self->_file_name($tag));
	$self->{tags}->{$tag}->{file}->append(sprintf("%s\n<urlset %s>\n", XML_HEAD, XML_MAIN_NAMESPACE));
}

sub _file_handle {
	my ($self, $tag) = @_;
	unless (exists $self->{tags}->{$tag}) {
		$self->{tags}->{$tag} = {
			page => 1,
			url_count => 0,
			file_size => 0
		};
		$self->_set_new_file($tag); 
	}

	return $self->{tags}->{$tag}->{file};
}

sub _next_file {
	my ($self, $tag) = @_;

	$self->_close_file($tag);
	$self->{tags}->{$tag}->{page}++;
	$self->{tags}->{$tag}->{url_count} = 0;
	$self->{tags}->{$tag}->{file_size} = 0;
	$self->_set_new_file($tag); 
}

sub _close_file {
	my ($self, $tag) = @_;
	$self->_file_handle($tag)->append("\n</urlset>");
	$self->_file_handle($tag)->close;
}

sub _file_name {
	my ($self, $tag, $page) = @_;
	return $self->{prefix}. $tag. '.'. ($page || $self->{tags}->{$tag}->{page}). '.xml'. ($self->{gzip} ? '.gz' : ''); 
}


1;


=head1 DESCRIPTION

Also support for Google images format:

	my @img_urls = (
		
		# Foramt 1
		{ 
			loc => 'http://test1.ru/', 
			images => { 
				caption_format => sub { 
					my ($iterator_value) = @_; 
					return sprintf('Вася - фото %d', $iterator_value); 
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
				caption_format_simple => 'Вася - фото',
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
			<caption><![CDATA[Вася - фото 1]]></caption>
		</image:image>
		<image:image>
			<loc>http://img2.ru</loc>
			<caption><![CDATA[Вася - фото 2]]></caption>
		</image:image>
	</url>
	<url>
		<loc>http://test11.ru/</loc>
		<image:image>
			<loc>http://img11.ru/</loc>
			<caption><![CDATA[Вася - фото 1]]></caption>
		</image:image>
		<image:image>
			<loc>http://img21.ru</loc>
			<caption><![CDATA[Вася - фото 2]]></caption>
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

=cut


=head1 AUTHOR

Mikhail N Bogdanov C<< <mbogdanov at cpan.org > >>

=cut






