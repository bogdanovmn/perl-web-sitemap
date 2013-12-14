package Web::Sitemap;

$VERSION = '0.02';

=head1 NAME
 Web::Sitemap - Simple way to generate sitemap files with paging support.
 Now it always use Gzip compress.
=cut

=head1 SYNOPSIS
 use Web::Sitemap;
 
 my $sm = Web::Sitemap->new(
	output_dir => '/path/to/sitemap'
 );

 $sm->add(\@url_list);
 $sm->add(\@url_list, {tag => 'articles'});
 $sm->add(\@url_list, {tag => 'users'});

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
		$self->{tags}->{$tag}->{file_size} = $fh->append(Web::Sitemap::Url->new($url)->to_xml_string);
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











