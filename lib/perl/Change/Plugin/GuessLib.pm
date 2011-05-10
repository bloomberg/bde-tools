package Change::Plugin::GuessLib;
use strict;

use base 'Change::Plugin::Base';

use Util::Message qw(fatal error message alert verbose);
use Util::File::Basename qw(dirname basename);
use Util::File::Functions qw (ensure_path);
use Change::Identity qw(deriveTargetfromName deriveTargetfromFile
			lookupName identifyProductionName);
use Change::Symbols qw(USER STAGE_PRODUCTION_LOCN STAGE_PREALPHA 
		       CSCOMPILE_TMP CHECKIN_ROOT FILE_IS_UNCHANGED
		       MOVE_REGULAR SCANT_N);
use Change::Set qw (addFile);

#==============================================================================

=head1 NAME

Change::Plugin::FindInc - plugin to SCANT's findinc tool

=head1 SYNOPSIS

Guess libraries for the files in changeset.

   $ cscheckout -LGuessLib <filename> ...

Stream candidate change set to a file and read change set from file:

    $ cscheckin -l -M -LGuessLib nalert/* news/* > candidate.set
    <edit candidate.set to remove unwanted files>
    $ cscheckin -a -f candidate.set

=head1 DESCRIPTION

This plugin searches for libraries for a file using Scant. 
 
=head2 Using GuessLib to generate a Candidate Change Set

The C<GuessLib> plugin is consistent with all cscheckin options including
redirecting the output to user specified file. Using the C<--list>/C<-l> and
C<--machine>/C<-M> options, it is possible to stream a candidate change set to
a file and edit the I<change set> prior to submission using C<--from>/C<-f>
option to read it in again.

=cut


#------------------------------------------------------------------------------

# run scant on the file
# if it returns many values, warn the user
# if it does not return anything check if this is mlfiles or bstfiles.
# 
  sub plugin_pre_find_filter ($$) {
      my ($plugin,$changeset)=@_;
      my $rcode=1; # Initially return code (rcode) is set to success
      alert "Searching for files which need target";
      
      foreach my $file ($changeset->getFiles) {
	  my $target = $file->getTarget();
	  my $name = $file->getLeafName;
	  	  
	  if(!defined $target || $target eq "") 
	  {
	      my @files = qx "${\SCANT_N} --lfp $name 2>/dev/null";
	     
	      if(scalar(@files) > 1) {
		  print "\nFile List:\n @files";
		  fatal "Scant reports more than one possible ,v file for $name";  
	      }
	      if(scalar(@files) < 1) {
		  fatal "Scant finds no $name file in repository.";     
	      }
	      ##<<TODO will be obsolete once scant db updates 2008.02.14  -gps
	      $files[0] =~ s/RCS\/// if($files[0] =~ /bbinc/);
	      my $source = `/usr/bin/dirname @files 2>/dev/null`;
	      chomp($source);
	      $source .= "/".$name;
	      $target = deriveTargetfromFile($source, STAGE_PREALPHA);
	      alert "\nFound target:$target for $name" if $target;
	      $file->setTarget($target);
	      
	  }
      }
      return 1;
      
  }
#==============================================================================

1;

=head1 AUTHOR

Nitin Khosla (nkhosla1@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Plugin::Example>, L<cscheckin>

=cut
