# iiif-scraper
Perl tool for downloading images from IIIF manifests

## Requirements
* Perl > 5.10
* Perl Modules
 * JSON
 * IO::Socket::SSL
 * Mozilla::CA
 * LWP::UserAgent
 * LWP::Simple
 * Data::Dumper
 * Getopt::Long


## Basic
`./iiif-scraper.pl --target=<TargetDir> --iiif=<ManifestURL>`
is the basic mode of operation.  It will create a directory named `TargetDir`, if one does not exist, and download an IIIF manifest from `ManifestURL`.  The manifest gets parsed and all images downloaded, with internal filename, to the `TargetDir`

## Optional Arguments

* `--verbose` -- Emit a bunch of debugging information to console
* `--numbers` -- Do not use the internal filename for images, simply number them in sequence
* `--labels` -- Rename the files to the value in the `label` in the manifest.  The label is slightly modified to be a filename, spaces are replaced with _ and numbers are 0-padded, so `fol. 123 v.jpg` becomes `fol._00123_v.jpg`
