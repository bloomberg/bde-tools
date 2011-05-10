package Util::File::Basename;
use strict;

BEGIN {
    require File::Basename; #avoid import
    File::Basename::fileparse_set_fstype("MSWin32") if $^O =~ /cygwin/;
}
use Exporter;
use vars qw(@ISA @EXPORT_OK);

@ISA=qw(Exporter);
@EXPORT_OK=qw(fileparse dirname basename fileparse_set_fstype);

#==============================================================================

=head1 NAME

Util::File::Basename - Directory separator-sensitive wrapper for File::Basename

=head1 SYNOPSIS

   use Util::File::Basename qw(basename dirname);

   my $basename=basename $0;
   my $run_from=dirname $0;

=head1 DESCRIPTION

Use this module in place of the standard L<File::Basename> for cross-platform
command-line generation.

While Perl is agnostic about the directory separator under Windows, tools
driven through a generated command line are frequently not. This module wraps
L<File::Basename> and corrects the directory separator so that the generated
pathnames are correct both for Perl and for external tools.

C<Util::File::Basename> also exports only on demand (i.e. no default exports),
to avoid polluting namespaces.

=cut

#==============================================================================

sub fileparse            { return File::Basename::fileparse(@_);            }
sub dirname              { return File::Basename::dirname(@_);              }
sub basename             { return File::Basename::basename(@_);             }
sub fileparse_set_fstype { return File::Basename::fileparse_set_fstype(@_); }

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<File::Basename>

=cut

1;
