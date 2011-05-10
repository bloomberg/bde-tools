package Remote::Exec;

use File::Basename;
use IO::Handle;

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw(
    readConfigFile
    getNextBuild
    setLog
    logMsg
    sendMail
    readEnvfile
    mkdirp
);

#------------------------------------------------------------------------------

sub readEnvfile($) {
    my $file = shift;
    open(FH, "<$file") or return undef;
    my @file = <FH>;
    close(FH) or return undef;
    for my $line (@file) {
        chomp $line;
        next if ! $line;
        my @temp;
        if ($line =~ /^(\w+)=(\S+)$/) {
            my $var = $1;
            my $val = $2;
            @temp = split /:/, $line;
            for my $v (@temp) {
                if ($v and $v =~ /\$(\w+)/ and $ENV{$1}) {
                    my $t = $1;
                    $val =~ s/%$t%/$ENV{$t}/g;
                }
            }
            $ENV{$var} = $val;
        }
    }
    return 1;
}

#------------------------------------------------------------------------------

#<<<TODO: use BDE::Build::Invocation qw($FS) for file separator
sub mkdirp ($) {
    my $fulldir = shift;
    my $path_sep = $^O eq "MSWin32" ? "\\" : "/";
    my @dirs = $^O eq "MSWin32" ? split /\\/, $fulldir : split /\//, $fulldir;
    my $dir = "";
    for (@dirs) {
        $dir .= "$_$path_sep";
	$dir=~/^(.*)$/ and $dir=$1;
        mkdir($dir, 0777) || return undef if ! -d $dir;
    }
    return 1;
}

#------------------------------------------------------------------------------

no strict "vars";

#------------------------------------------------------------------------------

sub readConfigFile ($) {
    my $configFile = shift;
    unless (my $rc = do $configFile) {
        die "couldn't parse config file $configFile: $@\n" if $@;
        die "couldn't do config file $configFile: $!\n" 
          unless defined $rc;
        die "couldn't run config file $configFile\n" unless $rc;
    }
    return($config{system});
}

#------------------------------------------------------------------------------

sub getNextBuild () {
    my $build = shift(@{$config{builds}});

    return if ! $build;
    my $platform = $$build{platform};
    my $hosts    = $$build{hosts};
    my $rshCmd   = $$build{rshCmd};
    my $slave    = $$build{slave};
    #my $args = " ";
    #for my $opt (keys %flags) {
    #    $args .= "$flags{$opt} $$build{$opt} " if $$build{$opt};
    #}
    return($platform, $hosts, $rshCmd, $slave);
}

#------------------------------------------------------------------------------

{
    my $LOG;
    my $MAILLOG;
    my $mailLog;
    my $interactive = 1 if -t STDIN && -t STDOUT;

    sub setLog($) {
        my @lt = localtime();
        my $ts = ($lt[4] + 1)."_$lt[3]-$lt[2]:$lt[1]:$lt[0]";
        my $l = shift;
        mkdirp(dirname($l)) or die "cannot mkdir for log $l: $!";
        my $log = $l.".".$ts;
        $mailLog = $l.".mail.".$ts;  # note scope
        open(LOG, "> $log") or die "cannot open $log: $!";
        LOG->autoflush(1);
        open(MAILLOG, "> $mailLog") or die "cannot open $mailLog: $!";
        MAILLOG->autoflush(1);
    }

    sub logMsg($;$) {
        my $msg = shift;
        my $flag = shift;  # unset=log only  1=tty  2=tty and mail
        my $d = localtime();
        print LOG "[$d] $msg\n";  # always log
        print MAILLOG "[$d] $msg\n" if $flag and $flag == 2;
        if ($flag and $interactive) {
            print "[$d] $msg\n";
        }
    }
              
    sub sendMail($$) {
        my $sub = shift;
        my $rc = shift;
        close(MAILLOG);  # has been left open...
        my $dst="rgibbons1\@bloomberg.net";
        if ($rc == 0) {
            system("/bb/bin/ratmail -s \"$sub COMPLETED OK\" $mailLog $dst");
        }
        elsif ($rc == 1) {
            system("/bb/bin/ratmail -s \"$sub FAILED\" $mailLog $dst");
        }
        unlink($mailLog);
    }

}

#------------------------------------------------------------------------------

1;
