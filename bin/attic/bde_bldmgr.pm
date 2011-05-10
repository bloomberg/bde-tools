#!/usr/local/bin/perl -w

# $Header: /usr/local/cvs/src/tools/jl/bde_bldmgr.pm,v 1.1 2002/09/24 12:48:53 rgibbons Exp $


package bde_bldmgr;

use Exporter;
@ISA = ('Exporter');
@EXPORT = qw(&read_config_file 
             &get_next_build
             &display_results);


########################################################################
# read_config_file - read build manager config file
########################################################################

sub read_config_file($;@) {
    my $config_file = shift;
    my @platforms = @_;
    unless (my $rc = do $config_file) {
        die "couldn't parse config file $config_file: $@\n" if $@;
        die "couldn't do config file $config_file: $!\n" unless defined $rc;
        die "couldn't run config file $config_file\n" unless $rc;
    }
    if (@platforms) {
        @builds = ();
        push @builds, ( { %sun_build } ) if grep /^sun$/, @platforms;
        push @builds, ( { %sun64_build } ) if grep /^sun64$/, @platforms;
        push @builds, ( { %dg_build } ) if grep /^dg$/, @platforms;
        push @builds, ( { %ibm_build } ) if grep /^ibm$/, @platforms;
        push @builds, ( { %ibm64_build } ) if grep /^ibm64$/, @platforms;
        push @builds, ( { %win_build } ) if grep /^win$/, @platforms;
    }
}


########################################################################
# get_next_build - return next build
########################################################################

sub get_next_build {
    return shift @builds;  #comes from $config_file
}


########################################################################
# display_results
########################################################################

sub display_results($) {
    my $results_array = shift;

    use constant ERR     => "N";
    use constant OK      => "y";
    use constant NA      => "-";
    use constant UNREACH => "X";
    use constant SYSTEM  => "SYSTEM";
    use constant BUILTON => "BUILD MACHINE";
    
    # Results stored as "results per system", but we need "results per 
    # target" - so extract relevant info and store into:
    #    @all_targets       - list of all *possible* targets
    #    @systems           - list of systems
    #    %results_by_target - hash of arrays
    #
    # NB - implicitly relies on system ordering in $results_array!
    
    my @all_targets;
    my @systems;
    my $maxtargetlen = 0;
    my $maxsystemlen = 0;
    my $ok_build = 1;
    
    # get all *possible* targets (could vary per system), all systems
    for my $result (@$results_array) {
        for my $result_target (@{$result->{targets}}) {
            push @all_targets, $result_target if 
              ! grep(/^$result_target$/, @all_targets);
            $maxtargetlen = length($result_target) if 
              $maxtargetlen < length($result_target);
        }
        push @systems, $result->{system};
        $maxsystemlen = length($result->{system}) if 
          $maxsystemlen < length($result->{system});
    }
    $maxsystemlen = length(SYSTEM) if $maxsystemlen < length(SYSTEM);
    @all_targets = sort @all_targets;
    
    # get results per target
    my %target_results;
    for my $target (@all_targets) {
        my @target_results;
        for my $result (@$results_array) {
            if ($result->{host}) {
                push(@target_results, OK), next if 
                  grep(/^$target$/, @{$result->{ok_targets}});
                if (grep(/^$target$/, @{$result->{err_targets}})) {
                    push(@target_results, ERR);
                    $ok_build = 0;
                    next;
                }
                push @target_results, NA;
            }
            else {
                push @target_results, UNREACH;
                $ok_build = 0;
            }
        }
        $target_results{$target} = \@target_results;
    }


    $ok_build and print "\n*** BUILD SUCCESSFUL ***\n\n" or 
      print "\n*** BUILD FAILED ***\n\n";
    
    # now print out matrix
    my $indent = $maxtargetlen + 3;
    my $colseplen = 3;
    print " " x ($indent);
    for (@systems) {
        print "$_" . " " x $colseplen;
    }
    print "\n";
    for my $target (@all_targets) {
        print "$target" . " " x ($indent - length($target));
        my $systems_i = 0;
        for my $result (@{$target_results{$target}}) {
            use integer;
            my $leadspaces = length($systems[$systems_i]) / 2;
            --$leadspaces if (length($systems[$systems_i]) % 2 == 0);
            my $trailspaces = length($systems[$systems_i]) - $leadspaces - 1;
            print " " x $leadspaces . "$result" . " " x $trailspaces;
            $systems_i++;
            print " " x $colseplen;
        }
        print "\n";
    }
    print "\n'" . ERR . "': failed  '" . OK . "': ok  '" . NA . "': N/A  " .
      "'" . UNREACH . "': system unreachable\n";
    
    # print out summary of what machines were built on
    print "\n\n" . SYSTEM . " " x ($maxsystemlen - length(SYSTEM) + 3) . 
      BUILTON . "\n\n";
    for my $results (@$results_array) {
        print "$results->{system}" . 
          " " x ($maxsystemlen - length($results->{system}) + 3);
        $results->{host} and print "$results->{host}\n" or 
          print "DID NOT BUILD\n";
    }
    
    # print out error summary per system
    for my $results (@$results_array) {
        next if $results->{host} and ! $results->{unreachable_hosts} and 
          ! $results->{err_targets};
        print "\n\n======== ERROR SUMMARY FOR $results->{system} ========\n";
        print "\n\nUNREACHABLE HOSTS: $results->{unreachable_hosts}\n" if
          $results->{unreachable_hosts};
        if ($results->{host}) {
            my %err_targets = map { ($_, 1) } @{$results->{err_targets}};
            for (sort keys %err_targets) {
                print "\ntarget $_ FAILED\n";
                print "$results->{err_msgs}->{$_}\n" if 
                  $results->{err_msgs}->{$_};
            }
        }
    }
    
    return $ok_build;
}

1;
