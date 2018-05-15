#!/usr/bin/perl -w

use strict;
use JSON;
use IO::Socket::SSL;
## there's nothing to "use" but we need it installed for SSL to verify
use Mozilla::CA;
use LWP::UserAgent;
use LWP::Simple;
use Data::Dumper;
use Getopt::Long;


### FUNCTION PROTOTYPES
sub retrieve_data($$);
sub get_iiif_urls($$);
sub url_to_filename($$$);
sub get_complete_image_url($);
sub help();
sub banner();
sub make_filenames($$);
sub get_iiif_elements($$$);


## variables will be set by CLI
my $url;
my $target_dir;
my $DEBUG;
my $numbers;
my $labels;
## parse the CLI arguments, set some values
GetOptions('iiif=s' => \$url,
           'target=s'     => \$target_dir,
           'verbose!'   => \$DEBUG,
	   'numbers!'    => \$numbers,
	   'labels!'     => \$labels,
);

## check for args
if (!defined $url){
	warn "--iiif is required parameter";
	help();
	exit 1;
}
if (!defined $target_dir){
	warn "--target is required parameter";
	help();
	exit 1;
}

## we have what we need
banner();
warn " Starting to download from ". $url;

my $json_string = retrieve_data($url, $DEBUG );

## decode the json
my $json_tool = JSON->new();
my $json_data = $json_tool->decode($json_string);

#print Dumper($json_data);
#exit ;
## pull the image urls out of the IIIF data
my $image_urls = get_iiif_urls($json_data, undef);
## get the labels if we need them, then make them filename safe
my $image_labels = get_iiif_elements($json_data, "label", $DEBUG);
$image_labels = make_filenames($image_labels, $DEBUG);
## we should have an array of images, if so, let's start downloading
if (ref($image_urls) eq 'ARRAY'){
	warn "We have an array of urls " . $#{$image_urls};
	if (!-d $target_dir){
		mkdir($target_dir) or die "Cannot create directory ". $target_dir;
	}
	## we should have a target directory, lets start downloading files!
	chdir($target_dir) or die "Cannot enter the target ". $target_dir;
	my $i=0;
	for my $image_url (@{$image_urls}){
	    my $filename = url_to_filename($image_url, "jpg", $DEBUG);
	    ## use weird filenames if desired
	    if ($numbers){
		$filename = sprintf("%05i.jpg", $i);
	    } elsif ($labels){
		$filename = $image_labels->[$i] . ".jpg";
	    }
	    my $http_code = getstore(
		get_complete_image_url($image_url),
		$filename
		);
	    if ($http_code != 200){
		warn "request to " . get_complete_image_url($image_url) . " returned " . $http_code;
	    }
	    $i++;
	}
}


## FUNCTIONS ##
######################################################################
##  Get the string via LWP
######################################################################

sub retrieve_data( $$ ){
    my ($full_url, $DEBUG) = @_;
    my $json_content;
    warn "  Preparing to retrieve\n $full_url" if ($DEBUG);
    my $ua=new LWP::UserAgent;
    $ua->timeout(15);
    
    my $request = new HTTP::Request('GET', $full_url); 
    my $response = $ua->request($request); 
    
    if ($response->is_error){
        die "Unable to retrieve URL $full_url: ". $response->status_line
    } else {
        warn "  Page retrieved" if ($DEBUG);
        $json_content = $response->content;
        warn $json_content if ($DEBUG);
    }
    return $json_content;
}

## pull out a list of image urls from an IIIF file.  Assume that the data is already in a structure, parsed from the json
## returns the arrayref to an array of image urls
sub get_iiif_urls( $$ ){
	my ($iiif_data, $DEBUG) = @_;
	## walk through the array sequence, pull out the buried @id elements
	my @urls;
	warn Dumper($iiif_data) if ($DEBUG);
	for my $canvas (@{$iiif_data->{'sequences'}->[0]->{'canvases'}}){
	    my $url = $canvas->{'images'}->[0]->{'resource'}->{'service'}->{'@id'};
	    warn "  " . $url if ($DEBUG);
	    push @urls, $url;
	}
	return \@urls;
}

## get a generic IIIF attribute from the parsed json
sub get_iiif_elements( $$$ ){
    my ($iiif_data, $element, $DEBUG) = @_;
    warn " Getting $element from iiif";
    my @data;
    for my $canvas (@{$iiif_data->{'sequences'}->[0]->{'canvases'}}){
	my $data_element = $canvas->{$element};
	warn "  " . $data_element if ($DEBUG);
	push @data, $data_element;
    }
    return \@data;
}
## take a url, return the last element as the filename.  append suffix
sub url_to_filename($$$){
	my ($url, $suffix, $DEBUG) = @_;
	warn " Getting filename from $url, adding $suffix" if ($DEBUG);
	my ($filename) = $url =~ /\/([^\/]+)$/;
	## we have some special logic to understand BAV urls, others might be added in later on
	## BAV filenames sometimes look like 4_0-AD2_fc5fc0a0fea162eb931d55e35d00650c0dd8d3bdb3e4ddf84854d4701bc58097_4133980799000_Vat.lat.3314.f.002v.jp2
	if ($url =~ /digi.vatlib.it.*\d{13}_[^\/]+\.jp2$/){
		($filename) = $url =~ /\d{13}_([^\/]+)\.jp2$/;
	} elsif ($url =~ /stacks.stanford.edu\/image\/iiif\/(.*)\%252(.*)$/){
## parker library urls look like this
## https://stacks.stanford.edu/image/iiif/jd913tp1831%252F540_fob_TC_4
		$filename=$2;
	} elsif ($url =~ /jp2$/){
		## is a jpg2000, we are ok with that
		($filename) = $url =~ /\/([^\/]+).jp2$/;
	}
	if (defined $suffix){
		$filename = $filename . '.' . $suffix;
	} 
	warn " Filename is $filename" if ($DEBUG);
	return $filename;
}

## append the junk to the urls to get the complete image file
sub get_complete_image_url($){
	my ($image_url) = @_;
	my $filename = "native.jpg";
	## fixup for parker at Stanford, uses default as filename
	if ($image_url =~ /stacks.stanford.edu/m){
		$filename = "default.jpg";
	}
	return $image_url . '/full/full/0/'.$filename;
}

## convert an array of strings to filename safe strings
sub make_filenames($$){
    my ($filenames, $DEBUG) = @_;
    warn "in make_filename" if ($DEBUG);
    my @clean_filenames;
    for my $filename (@{$filenames}){
	warn " $filename" if ($DEBUG);
	##format numbers, if they are there
	if ($filename =~ /.*\d.*/){
	    my ($pre,$num,$post) = $filename =~ /^([^0-9]*)(\d*)(.*)$/;
	    $filename = sprintf("%s%05i%s", $pre,$num,$post);
	}
	## cleanup spaces
	$filename =~ s/\s+/_/g;
	push @clean_filenames, $filename;
	warn " cleaned to $filename" if ($DEBUG);
    }
    return \@clean_filenames;
}


## just display a normal banner about usage and rights
sub banner(){
	warn "  Please respect the rights of the holding institution where applicable.  ";
	return;
}

## basic usage
sub help(){
    print <<EOF;
$0 - a tool to download all of the web-images from an IIIF manifest. Required arguments:
	--iiif=ManifestURL -- URL to the manifest, can be either HTTP or HTTPS
	--target=Directory -- directory to save the images, will create if does not exist
Optional Arguments:
	--verbose -- display a bunch of debugging information to the console
	--numbers -- Rename the images with sequence numbers
	--labels -- Rename the images to the value of the `label` element of the manifest
EOF
    return;
}
