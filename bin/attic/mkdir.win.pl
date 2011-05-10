#!/usr/local/bin/perl
my $fulldir;
for my $dir (split("/", $ARGV[0])) {
  $fulldir .= "$dir/";
  mkdir($fulldir, 0777);
}
