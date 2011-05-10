package Change::Plugin::Manager;
use strict;

use base 'BDE::Object';

use Util::Message qw(fatal debug warning);

use Change::Symbols qw(/^APPROVE_/);

#==============================================================================

=head1 NAME

Change::Plugin::Manager - Manage a collection of cscheckin plugins

=head1 SYNOPSIS

    use Change::Plugin::Manager;

    my $manager=new Change::Plugin::Manager;
    $manager->load("MyPlugin");
    $manager->load("OtherPlugin");

    $manager->initialize($href);
    ...
    $manager->finialize($href);

=head1 DESCRIPTION

C<Change::Plugin::Manager> is a container class providing management for a
collection of cscheckin plugins, themselves represented by instances of
derived classes of the C<Change::Plugin::Base> plugin base class. It provides
methods to add, remove, extract, and invoke plugins in order.

The methods in this object class are divided into two functional groups: the
constuctor and accessor/mutator methods maintain the state of the manager
itself, and are documented immediately below. The plugin interface methods,
described in L<"PLUGIN INTERFACE">, are called by scripts that implement the
plugin interface, and are responsible for calling the identically named methods
in the plugins that are registered with the manager.

=cut

#==============================================================================
# Constructor support

=head1 CONSTRUCTORS

=head2 new([$aref])

Create a new empty instance of a C<Change::Plugin::Manager> object.

If an array reference argument is supplied containing already constructed
plugin objects, the manager is populated with them. The order of plugins in the
array is the order in which they will be processed.

=cut

sub initialise ($$) {
    my ($self,$init)=@_;
    $self->SUPER::initialise($init);
    $self->{plugins} ||= [];
    $self->{index} ||= {};
    # tool register here with the manager
    $self->{toolname} ||= "";
    debug "Plugin Manager initializing.";
    debug "Initialize arguments: '$init' \n" if defined $init;
}

# same as initialise from Scalar
sub fromString($$) {
    my ($self, $string)=@_;
    $self->{toolname} = $string;
}

# Constructor support - from an array reference
sub initialiseFromArray ($$;$) {
    my ($self,$aref,$init)=@_;

    $self->throw("Initialiser passed argument not an array reference")
      unless UNIVERSAL::isa($aref,"ARRAY");

    # a name may be passed in as 2nd arg, or first element of arrayref
    if (not $init and not ref $aref->[0]) {
	$init=shift @$aref;
    }
    if ($init) {
	$self->setName($init);
    }

    $self->{plugins} = [];
    $self->{index} = {};

    foreach my $pluginno (0 .. @$aref) {
	my $plugin=$aref->[$pluginno];
	next unless $plugin;
        $self->addPlugin($plugin);
    }
    
    # where is this function??
    $self->setDefault();

    return 0; # continue
}

#------------------------------------------------------------------------------
# Accessors/Mutators

=head1 ACCESSORS/MUTATORS

=head2 getToolId()

Get the toolname supported for the plugin.

=cut

sub getToolId($) {
    my ($self)=@_;

    return  $self->{toolname};
}


=head2 setToolId($name)

Set the toolname supported for the plugin.

=cut

sub setToolId($$) {
    my ($self,$name)=@_;

    $self->{toolname}=$name;
}



=head2 getPlugin($index)

Return the plugin at the specified index from the log, or C<undef> if the
plugin is not present.

=cut

sub getPlugin ($$) {
    my ($self,$index)=@_;

    if (abs($index) < scalar(@{$self->{plugins}})) {
	return $self->{plugins}[$index];
    }

    return undef;
}

=head2 getPluginIndex($name)

Return the index of the plugin with the given name, or C<undef> if no plugin
of that name is currently loaded.

=cut

sub getPluginIndex ($$) {
    my ($self,$name)=@_;

    if (exists $self->{index}{$name}) {
	return $self->{index}{$name};
    }

    return undef;
}

=head2 getPlugins()

Return a list of all plugins currently registered.

=cut

sub getPlugins ($) {
    my ($self)=@_;

    return @{$self->{plugins}};
}

=head2 addPlugin($plugin)

Add the specified plugin to the manager. This implies an already existing
plugin instance. To load a plugin, use L<"load"> instead.

=cut

sub addPlugin ($$) {
    my ($self,$plugin)=@_;

    $self->throw("Not a plugin - $plugin"),return undef
      unless $plugin->isa("Change::Plugin::Base");

    my $index=$self->getPluginIndex($plugin);
    if (defined $index) {
	debug "Plugin $plugin already loaded at index $index -- ignored";
	return $self->getPlugin($index);
    }

    push @{$self->{plugins}},$plugin;
    $self->{index}{$plugin}=$#{$self->{plugins}};

    return 1;
}

=head2 addPlugins(@plugins)

Add one or more plugins to the manager.

=cut

sub addPlugins ($@) {
    my ($self,@plugins)=@_;

    foreach my $plugin (@plugins) {
	return undef unless $self->addPlugin($plugin);
    }

    return 1;
}

=head2 removePlugin($index)

Remove and return the plugin at the supplied index from the log.
Returns C<undef> if the index is not present.

=cut

sub removePlugin ($$) {
    my ($self,$index)=@_;

    foreach my $name (keys %{$self->{index}}) {
	delete $self->{index}{$name}
	  if $self->{index}{$name} == $index;
    }
    return splice @{$self->{plugins}},$index,1;
}

=head2 removePluginByName($name)

Remove the plugin with the supplied name. Returns C<undef> if that
plugin was never loaded. A true value otherwise.

=cut

sub removePluginByName {
    my ($self, $name) = @_;

    my $index = $self->getPluginIndex($name);

    return if not defined $index;

    $self->removePlugin($index);

    return 1;
}

=head2 removePlugins(@indices)

Remove one or more plugins by index, if they exist.

=cut

sub removePlugins ($@) {
    my ($self,@indices)=@_;

    return map { $_->removePlugin() } @indices;
}

=head2 removeAllPlugins()

Remove all currently resident plugins.

=cut

sub removeAllPlugins ($) {
    my $plugins=$_[0]->{plugins};
    $_[0]->{plugins}=[];
    $_[0]->{index}={};
    return @$plugins if defined wantarray;
}

=head2 load($name)

Load the plugin with the given name, and add it to the manager if successful,
returning the plugin module to the caller. Throw an exception if the plugin
could not be loaded. If a plugin with the given name is already loaded then
return it is returned and no additional actions are taken.

The module name is derived from the plugin name by prepending the
C<Change::Plugin::> namespace to it. (Loading of modules outside this
namespace is explicitly not supported.)

=cut

sub load ($$) {
    my ($self,$plugin)=@_;

    my $index=$self->getPluginIndex($plugin);
    if (defined $index) {
	debug "Plugin $plugin already loaded at index $index -- ignored";
	return $self->getPlugin($index);
    }

    my $module="Change::Plugin::".$plugin;
    my ($args,@args);

    if ($module=~/=/) {
	($module,$args)=split /=/,$module;
	@args=split /,/,$args;
    }

    debug "Loading plugin module $module";
    if (@args) {
	eval "use $module qw(@args)";
    } else {
	eval "use $module";
    }
    fatal "Unable to load plugin $plugin: $@" if $@;
    $plugin=$module->new();
    my @names = $plugin->getSupportedTools();
    my $isPresent = map { $_ =~ /^$self->{toolname}$/ } @names;
    debug "Toolname: $self->{toolname}, Plugin support: $isPresent";    
    # if names=empty then plugin can be used by all tools
    if(@names && !$isPresent){
	warning "WARNING: Plugin '".$plugin->name()."' cannot be called by this tool.";
	return undef;
    }
    $self->addPlugin($plugin);
    # setting the toolname in plugin
    $plugin->setToolId($self->{toolname});
    return $plugin;
}

=head2 loadApprovalPlugin($name);

Load a plugin for the specified approval type, if one is applicable. Return
the plugin, if one was loaded, or undef otherwise.

Approval plugins are located in the C<Change::Plugin::Approval> namespace,
and are automatically loaded by scripts when appropriate. The name of the
plugin is associated with the approval type in this routine.

=cut

sub loadApprovalPlugin ($) {
    my ($self,$name)=@_;
    my $plugin;
    my $plugin_name;

    $plugin_name="TSMV"	    if $name eq APPROVE_TSMV;
    $plugin_name="PRQSCR"   if $name eq APPROVE_PRQSCR;
    $plugin_name="BBMV"	    if $name eq APPROVE_BBMV;
    # other mappings here when applicable

    if ($plugin_name) {
	$plugin=$self->load("Approval::".$plugin_name);
    }

    return $plugin;
}

#------------------------------------------------------------------------------

=head1 PLUGIN INTERFACE

All C<plugin_> methods provided by C<Change::Plugin::Base>, with the exception
of L<plugin_ismanual>, are also implemented polymorphically by the manager.
For each method, the manager will call the same method for every registed
plugin.

=head2 Plugin Calling Order

The order in which plugins are registered determines the order in which they
are called. Depending on the method, the order is either forward (i.e first
registered, first called) or reversed (last registered, first called). This
mimics the concept of a constructor/destructor calling order, and is also in
the vein of Perl's C<BEGIN> vs C<END> blocks.

The calling order for each plugin interface method is as follows:

    n/a       plugin_ismanual()
    forward   plugin_usage()
    forward   plugin_options()
    forward   plugin_initialize($opts)
    forward   plugin_pre_find_filter($changeset)
    forward   plugin_post_find_filter($changeset)
    forward   plugin_early_interaction($opts,$interact)
    forward   plugin_late_interaction($opts,$interact)
    forward   plugin_pre_change($changeset)
    forward   plugin_pre_file($changeset,$changefile)
    backward  plugin_post_file($changeset,$changefile)
    backward  plugin_post_change_success($changeset)
    backward  plugin_post_change_failure($changeset)
    backward  plugin_finalize($opts,$exit_code)

The return value of each method is derived from the combination of return
values from the individual plugins:

=over 4

=item * C<plugin_usage> concatenates the string outputs with an intervening
        newline.

=item * C<plugin_options> combines the list values into one list.

=item * All other plugin methods return true if all the individual plugin
        methods return true, or false if any plugin method returned false.

=back

See L<Change::Plugin::Base> for more information on plugin methods.

=cut

sub plugin_usage ($) {
    my $self=shift;

    my @usage;
    foreach my $plugin ($self->getPlugins) {
	my $usage=$plugin->plugin_usage();
	push @usage,"Plugin $plugin:\n\n$usage\n" if $usage;
    }

    return join "\n",@usage;
}

sub plugin_options ($) {
    my $self=shift;

    return (map { $_->plugin_options() } $self->getPlugins);
}

sub plugin_initialize ($$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_initialize(@_);
    }
    return $result;
}

sub plugin_pre_find_filter ($$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_pre_find_filter(@_);
    }
    return $result;
}

sub plugin_post_find_filter ($$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_post_find_filter(@_);
    }
    return $result;
}

sub plugin_early_interaction ($$$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_early_interaction(@_);
    }
    return $result;
}

sub plugin_late_interaction ($$$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_late_interaction(@_);
    }
    return $result;
}

sub plugin_pre_change ($$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_pre_change(@_);
    }
    return $result;
}

sub plugin_pre_file ($$$) {
    my $self=shift;

    my $result=1;
    foreach ($self->getPlugins) {
	$result=0 unless $_->plugin_pre_file(@_);
    }
    return $result;
}

# forward
#---
# reverse

sub plugin_post_file ($$$) {
    my $self=shift;

    my $result=1;
    foreach (reverse $self->getPlugins) {
	$result=0 unless $_->plugin_post_file(@_);
    }
    return $result;
}

sub plugin_post_change_success ($$) {
    my $self=shift;

    my $result=1;
    foreach (reverse $self->getPlugins) {
	$result=0 unless $_->plugin_post_change_success(@_);
    }
    return $result;
}

sub plugin_post_change_failure ($$) {
    my $self=shift;

    my $result=1;
    foreach (reverse $self->getPlugins) {
	$result=0 unless $_->plugin_post_change_failure(@_);
    }
    return $result;
}

sub plugin_finalize ($$$) {
    my $self=shift;

    my $result=1;
    foreach (reverse $self->getPlugins) {
	$result=0 unless $_->plugin_finalize(@_);
    }
    return $result;
}

#==============================================================================

=head1 AUTHOR

Peter Wainwright (pwainwright@bloomberg.net)

=head1 SEE ALSO

L<Change::Plugin::Base>, L<Plugin::Example>, L<cscheckin>

=cut

1;
