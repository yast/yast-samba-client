#! /usr/bin/perl
# File:		modules/SambaConfig.pm
# Package:	Configuration of samba-server
# Summary:	Manage samba configuration data (smb.conf).
# Authors:	Martin Lazar <mlazar@suse.cz>
#
# $Id$
#
# Functions for acess to samba configuration file. It provide
# unified acces to configuration keys including aliases and other
# difficulty.
#

package SambaConfig;

use strict;

use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

YaST::YCP::Import("SCR");


###########################################################################
# variables
my %Config;	# configuration hash


###########################################################################
# global (static) variables (constants)


# synonyms hash
my %Synonyms = (
    "timestamp logs" => "debug timestamp",
    "default" => "default service",
    "winbind gid" => "idmap gid",
    "winbind uid" => "idmap uid",
    "lock dir" => "lock directory",
    "debuglevel" => "log level",
    "protocol" => "max protocol",
    "min password len" => "min password length",
    "prefered master" => "preferred master",
    "auto services" => "preload",
    "root" => "root directory",
    "root dir" => "root directory",
    "browsable" => "browseable",
    "casesignames" => "case sensitive",
    "create mode" => "create mask",
    "directory mode" => "directory mask",
    "group" => "force group",
    "public" => "guest ok",
    "only guest" => "guest only",
    "allow hosts" => "hosts allow",
    "deny hosts" => "hosts deny",
    "directory" => "path",
    "exec" => "preexec",
    "print ok" => "printable",
    "printcap" => "printcap name",
    "printer" => "printer name",
    "user" => "username",
    "users" => "username",
    "vfs object" => "vfs objects",
    "writable" => "writeable",
);

# inverted synonyms hash    
my %InvertedSynonyms = ( 
    "writeable" => "read only",
    "writable" => "read only",
);


###########################################################################
# helper functions

# nomralize boolean value
sub toboolean {
    my $val = shift;
    return undef unless defined $val;
    return 0 if $val =~ /^\s*(no|false|disable|0+)\s*$/i;
    return 0 unless $val;
    return 1;
}


###########################################################################
# public methods

# return modified status
BEGIN{ $TYPEINFO{GetModified} = ["function", "boolean"]; }
sub GetModified {
    my ($self) = @_;
    foreach (keys %Config) {
	return 1 if $Config{$_}{_modified};
    }
    return 0;
}

# set modified status
BEGIN{ $TYPEINFO{SetModified} = ["function", "void"]; }
sub SetModified {
    my ($self) = @_;
    $Config{"global"}{_modified} = 1;
}

# dump configuration to STDOUT (for debugging only)
BEGIN{ $TYPEINFO{Dump} = ["function", "void"]; }
sub Dump {
    my $self = shift;
    print Data::Dumper->Dump(
	[\%Config], [qw(Config)]
    );
}

sub config2all {    
    my ($config, $share) = @_;
    my @section;
    my $out = { 
	kind =>		"section", 
	name=>		$share,
	value=>		[], 
	type=>		Integer($config->{$share}{_disabled}?1:0), 
	comment=>	$config->{$share}{_comment}
    };
    my $type = $out->{type} = $config->{$share}{$_};
    foreach(keys %{$config->{$share}}) {
	next if /^_/;
        push @{$out->{value}}, { kind=>"value", name=>$_, value=>$config->{$share}{$_}, type=>$out->{type} };
    }
    return $out;
}

# convert configuration map to format suitable for SRC Read/Write all-at-once
BEGIN{ $TYPEINFO{Config2All} = ["function", ["map", "any", "any"], ["map", "any", "any"]]; }
sub Config2All {
    my ($self, $config) = @_;
    my @out;
    foreach("global", "homes", "printers", "netlogon") {
	push @out, config2all($config, $_) if $config->{$_};
    }
    foreach(keys %$config) {
	next if /^_/;
	next if /^(global|homes|printers|netlogon)$/;
	push @out, config2all($config, $_);
    }
    return {value=>\@out, kind=>"section", type=>Integer(-1), file=>Integer(-1), name=>"", comment=>""};
}


# read configuration from file
BEGIN{ $TYPEINFO{Read} = ["function", "boolean", "boolean"]; }
sub Read {
    my ($self, $forceReRead) = @_;

    # coniguraton already readed
    return 1 if not $forceReRead and %Config;
    
    # forget previous configuration
    %Config = ();

    # read the complete global section
    my $AllAtOnce = SCR->Read(".etc.smb.all");

    # convert .ini agent all-at-once map to %Config
    foreach my $section (@{$AllAtOnce->{value}}) {
	next if $section->{kind} ne "section";
	my $share = $section->{name};

	# disabled (comment-out) share
	$Config{$share}{_disabled} = 1 if $section->{type};
	$Config{$share}{_comment} = $section->{comment};

	foreach my $line (@{$section->{value}}) {
	    next if $line->{kind} ne "value";
	    next if $line->{type} and not $section->{type}; # commented line

	    $self->ShareSetStr($share, $line->{name}, $line->{value});
	}
    }
    
    y2debug("Readed config: ".Dumper(\%Config));
    return 1;
}

# write configuration to file
# TODO: use all-at-once write
BEGIN{ $TYPEINFO{Write} = ["function", "boolean", "boolean"]; }
sub Write {
    my ($self, $forceWrite) = @_;

    y2debug("modified flag is ".($self->GetModified()?"set":"not set"));
    return 1 unless $forceWrite or $self->GetModified();

    # first, write the global settings complete
    if ($forceWrite or $Config{global}{_modified}) {
	foreach my $key (sort keys %{$Config{global}}) {
	    next if $key =~ /^_/;	# skip internal keys
	    my $val = $Config{global}{$key};
	    if (!defined $val) {
		SCR->Write(".etc.smb.value.global.$key", undef);
	    } else {
	        SCR->Write(".etc.smb.value.global.$key", String($val));
	        # ensure option is not commented
		SCR->Write(".etc.smb.value_type.global.$key", Integer(0));
	    }
	}

	# ensure global section is not commented
	SCR->Write(".etc.smb.section_type.global", Integer(0));
	
	# remove modified flag
	$Config{global}{_modified} = undef;
    }

    # remove removed shares first
    foreach my $share (sort grep {!$Config{$_}} keys %Config) {
	SCR->Write(".etc.smb.section.$share", undef);
    };
    $Config{_removed} = undef; # remove modified flag

    # write shares
    foreach my $share (sort keys %Config) {
	next unless $Config{$share};	# skip removed shares
	next if $share eq "global";	# skip global section
	next if $share =~ /^_/;		# skip internal shares
	next unless $forceWrite || $Config{$share}{_modified};

	# prepare the right type for writing out the value
	my $commentout = $Config{$share}{_disabled} ? 1 : 0;
	
	# write all the options
	foreach my $key (sort keys %{$Config{$share}}) {
	    next if $key =~ /^_/;	# skip our internal options
	    my $val = $Config{$share}{$key};
	    if (!defined $val) {
		SCR->Write(".etc.smb.value.$share.$key", undef);
	    } else {
	        my $ret1 = SCR->Write(".etc.smb.value.$share.$key", String($val));
	        my $ret  = SCR->Write(".etc.smb.value_type.$share.$key", Integer($commentout));
	    }
	};
	
	# write the type and comment of the section
	SCR->Write(".etc.smb.section_type.$share", Integer($commentout));
	my $comment = $Config{$share}{_comment} || "";
	if (!$commentout) {
	    $comment =~ s/[;#]+\s*Share disabled by YaST\s*\n//gi;
	} elsif ($comment !~ /.*Share.*Disabled.*/i) {
	    $comment .= "## Share disabled by YaST\n";
	}
	$comment = "\n" unless $comment;
	SCR->Write(".etc.smb.section_comment.$share", String($comment));

	# remove modified flag
	$Config{$share}{_modified} = undef;
    };
    
    # commit the changes
    if (!SCR->Write(".etc.smb", undef)) {
	y2error("Cannot write settings to /etc/samba/smb.conf");
	return 0;
    }

    return 1;
}

# return list of shares
BEGIN{ $TYPEINFO{GetShares} = ["function", ["list", "string"]]; }
sub GetShares {
    my ($self) = @_;
    return [ grep {!/^(_.*|global)$/ and defined $Config{$_}} keys %Config ];
}

# return true if configured
BEGIN{ $TYPEINFO{Configured} = ["function", "boolean"]; }
sub Configured {
    my ($self) = @_;
    return keys %Config ? 1 : 0;
}

# export configuration
BEGIN{ $TYPEINFO{Export} = ["function", "any"]; }
sub Export {
    my ($self) = @_;
    # remove modified flags and internal shares from config
    my @myconfig;
    foreach my $share (keys %Config) {
	next unless $Config{$share};	# skip removed shares
	next if $share =~ /^_/;		# skip internal shares
	my %section;
	$section{name} = $share;
	$section{comment} = $Config{$share}{_comment} if $Config{$share}{_comment};
	$section{disabled} = Boolean(1) if $Config{$share}{_disabled};
	while(my ($key, $val) = each %{$Config{$share}}) {
	    next unless defined $val;	# skip undefined values
	    next if $key =~ /^_/;	# skip internal keys
	    $key =~ tr/a-zA-Z/_/cs;
	    $section{parameters}{lc $key} = $val;
	}
	push @myconfig, \%section;
    }
    return \@myconfig;
}

# import configuration
BEGIN{$TYPEINFO{Import} = ["function", "void", "any"]}
sub Import {
    my ($self, $config) = @_;
    %Config = ();
    if ($config) {
	foreach my $section (@$config) {
	    my $name = $section->{name};
	    next unless $name;
	    $Config{$name}{_comment} = $section->{comment} if $section->{comment};
	    $Config{$name}{_disabled} = 1 if $section->{disabled};
	    while(my ($key, $val) = each %{$section->{parameters}}) {
		$key =~ tr/_/ /;
		$Config{$name}{$key} = $val;
	    }
	}
    }
    y2debug("Imported config: ".Dumper(\%Config));
}

###########################################################################
# general shares

# remove share
BEGIN{ $TYPEINFO{ShareRemove} = ["function", "boolean", "string"]; }
sub ShareRemove {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return 0 unless defined $Config{$share};
    $Config{$share} = undef;
    $self->ShareSetModified("_removed");
    y2debug("ShareRemove($share)");
    return 1;
}

# return true if share exists
BEGIN{ $TYPEINFO{ShareExists} = ["function", "boolean", "string"]; }
sub ShareExists {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return defined $Config{$share};
}

# get share keys
BEGIN{ $TYPEINFO{ShareKeys} = ["function", ["list", "string"], "string"]; }
sub ShareKeys {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return [] unless defined $Config{$share};
    return [ grep {$_!~/^_/ and defined $Config{$share}{$_}} keys %{${Config{$share}}} ];
}

# get share key value
BEGIN{ $TYPEINFO{ShareGetStr} = ["function", "string", "string", "string", "string"]; }
sub ShareGetStr {
    my ($self, $share, $key, $default) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    if (not defined $key) {
	y2error("undefned key");
	return undef;
    }
    $key = lc($key);
    $key = $Synonyms{$key} if exists $Synonyms{$key};
    if (exists $InvertedSynonyms{$key}) {
	$key = $InvertedSynonyms{$key};
	my $val = toboolean($Config{$share}{$key});
	return defined $val ? ($val ? "No" : "Yes") : $default;
    }
    return defined $Config{$share}{$key} ? $Config{$share}{$key} : $default;
}

# set share key value, return old value
BEGIN{ $TYPEINFO{ShareSetStr} = ["function", "boolean", "string", "string", "string"]; }
sub ShareSetStr {
    my ($self, $share, $key, $val) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    if (not defined $key) {
	y2error("undefned key");
	return undef;
    }
    my $modified = 0;
    $key = lc($key);
    $key = $Synonyms{$key} if exists $Synonyms{$key};
    if (exists $InvertedSynonyms{$key}) {
	$key = $InvertedSynonyms{$key};
	my $old = toboolean($Config{$share}{$key});
	if (defined $val) {
	    $val = 1-toboolean($val);
	    $modified = 1 unless defined $old and $old == $val;
    	    $Config{$share}{$key} = $val ? "Yes" : "No";
	} else {
	    $modified = 1 if defined $old;
#	    delete $Config{$share}{$key};
	    $Config{$share}{$key} = undef;
	}
    } else {
	my $old = $Config{$share}{$key};
	if (defined $val) {
	    $modified = 1 unless defined $old and $old eq $val;
	    $Config{$share}{$key} = $val;
	} else {
    	    $modified = 1 if defined $old;
#	    delete $Config{$share}{$key};
	    $Config{$share}{$key} = undef;
	}
    }
    $self->ShareSetModified($share) if $modified;
    y2debug("ShareSetStr($share, $key, ".($val||"<undef>").")") if $modified;
    return $modified;
}

# get share key value as boolean
BEGIN{ $TYPEINFO{ShareGetTruth} = ["function", "boolean", "string", "string", "boolean"]; }
sub ShareGetTruth {
    my ($self, $share, $key, $default) = @_;
    return toboolean($self->ShareGetStr($share, $key, defined $default ? ($default ? "Yes" : "No") : undef));
}

# get share key value as integer
BEGIN{ $TYPEINFO{ShareGetInteger} = ["function", "integer", "string", "string", "integer"]; }
sub ShareGetInteger {
    my ($self, $share, $key, $default) = @_;
    return $self->ShareGetStr($share, $key, $default);
}

# set share key value as boolean
BEGIN{ $TYPEINFO{ShareSetTruth} = ["function", "boolean", "string", "string", "boolean"]; }
sub ShareSetTruth {
    my ($self, $share, $key, $val) = @_;
    return $self->ShareSetStr($share, $key, (defined $val ? ($val ? "Yes" : "No") : undef));
}

# get share key value as integer
BEGIN{ $TYPEINFO{ShareSetInteger} = ["function", "boolean", "string", "string", "integer"]; }
sub ShareSetInteger {
    my ($self, $share, $key, $val) = @_;
    return $self->ShareSetStr($share, $key, $val);
}

# enable share
BEGIN{ $TYPEINFO{ShareEnable} = ["function", "boolean", "string"]; }
sub ShareEnable {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return undef unless $self->ShareExists($share);
    if ($Config{$share}{_disabled}) {
	delete $Config{$share}{_disabled};
	y2debug("ShareEnable($share)");
	return 1;
    }
    return 0;
}

# enable share
BEGIN{ $TYPEINFO{ShareDisable} = ["function", "boolean", "string"]; }
sub ShareDisable {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return undef unless $self->ShareExists($share);
    unless ($Config{$share}{_disabled}) {
	$Config{$share}{_disabled} = 1;
	y2debug("ShareDisable($share)");
	return 1;
    }
    return 0;
}

# enable/disable share
BEGIN{ $TYPEINFO{ShareAdjust} = ["function", "boolean", "string", "boolean"]; }
sub ShareAdjust {
    my ($self, $share, $adjust) = @_;
    return $adjust ? $self->ShareEnable($share) : $self->ShareDisable($share);
}

# is share enabled
BEGIN{ $TYPEINFO{ShareEnabled} = ["function", "boolean", "string"]; }
sub ShareEnabled {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return undef unless $self->ShareExists($share);
    return $Config{$share}{_disabled}?0:1;
}

# return share
BEGIN{ $TYPEINFO{ShareGetMap} = ["function", ["map", "string", "string"], "string"]; }
sub ShareGetMap {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    my %ret;
    my $keys = $self->ShareKeys($share);
    foreach(@$keys) {
	$ret{$_} = $Config{$share}{$_};
    }
    return \%ret;
}

# set share
BEGIN{ $TYPEINFO{ShareSetMap} = ["function", "boolean", "string", ["map", "string", "string"]]; }
sub ShareSetMap {
    my ($self, $share, $map) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    my $modified = 0;
    foreach(keys %$map) {
	$modified |= $self->ShareSetStr($share, $_, $map->{$_});
    }
    return $modified;
}

# update share
BEGIN{ $TYPEINFO{ShareUpdateMap} = ["function", "boolean", "string", ["map", "string", "string"]]; }
sub ShareUpdateMap {
    my ($self, $share, $map) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    my $modified = 0;
    foreach(keys %$map) {
	$modified |= $self->ShareSetStr($share, $_, $map->{$_})
	    unless defined $self->ShareGetStr($share, $_, undef);
    }
    return $modified;
}

# set share modified
BEGIN{ $TYPEINFO{ShareSetModified} = ["function", "void", "string"]; }
sub ShareSetModified {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    $Config{$share}{_modified} = 1;
}

# get share modified
BEGIN{ $TYPEINFO{ShareGetModified} = ["function", "boolean", "string"]; }
sub ShareGetModified {
    my ($self, $share) = @_;
    if (not defined $share) {
	y2error("undefned share");
	return undef;
    }
    return $Config{$share}{_modified} ? 1 : 0;
}

# get share comment
BEGIN{ $TYPEINFO{ShareGetComment} = ["function", "string", "string"]; }
sub ShareGetComment {
    my ($self, $share) = @_;
    return $self->ShareGetStr($share, "_comment", undef);
}

# get share comment
BEGIN{ $TYPEINFO{ShareSetComment} = ["function", "void", "string", "string"]; }
sub ShareSetComment {
    my ($self, $share, $comment) = @_;
    return $self->ShareSetStr($share, "_comment", $comment);
}


###########################################################################
# Homes

BEGIN{ $TYPEINFO{HomesRemove} = ["function", "boolean"]; }
sub HomesRemove { return ShareRemove(shift, "homes"); }

BEGIN{ $TYPEINFO{HomesExists} = ["function", "boolean"]; }
sub HomesExists { return ShareExists(shift, "homes"); }

BEGIN{ $TYPEINFO{HomesKeys} = ["function", ["list", "string"]]; }
sub HomesKeys { return ShareKeys(shift, "homes"); }

BEGIN{ $TYPEINFO{HomesGetStr} = ["function", "string", "string", "string"]; }
sub HomesGetStr { return ShareGetStr(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesSetStr} = ["function", "boolean", "string", "string"]; }
sub HomesSetStr { return ShareSetStr(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesGetTruth} = ["function", "boolean", "string", "boolean"]; }
sub HomesGetTruth { return ShareGetTruth(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesSetTruth} = ["function", "boolean", "string", "boolean"]; }
sub HomesSetTruth { return ShareSetTruth(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesGetInteger} = ["function", "integer", "string", "integer"]; }
sub HomesGetInteger { return ShareGetInteger(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesSetInteger} = ["function", "boolean", "string", "integer"]; }
sub HomesSetInteger { return ShareSetInteger(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesEnable} = ["function", "boolean"]; }
sub HomesEnable { return ShareEnable(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesDisable} = ["function", "boolean"]; }
sub HomesDisable { return ShareDisable(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesAdjust} = ["function", "boolean", "boolean"]; }
sub HomesAdjust { return ShareAdjust(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesEnabled} = ["function", "boolean"]; }
sub HomesEnabled { return ShareEnabled(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesSetMap} = ["function", "boolean", ["map", "string", "string"]]; }
sub HomesSetMap { return ShareSetMap(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesUpdateMap} = ["function", "boolean", ["map", "string", "string"]]; }
sub HomesUpdateMap { return ShareUpdateMap(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesGetMap} = ["function", ["map", "string", "string"]]; }
sub HomesGetMap { return ShareGetMap(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesSetModified} = ["function", "void"]; }
sub HomesSetModified { return ShareSetModified(shift, "homes", @_); }

BEGIN{ $TYPEINFO{HomesGetModified} = ["function", "boolean"]; }
sub HomesGetModified { return ShareGetModified(shift, "homes", @_); }


###########################################################################
# Global

BEGIN{ $TYPEINFO{GlobalRemove} = ["function", "boolean"]; }
sub GlobalRemove { return ShareRemove(shift, "global"); }

BEGIN{ $TYPEINFO{GlobalExists} = ["function", "boolean"]; }
sub GlobalExists { return ShareExists(shift, "global"); }

BEGIN{ $TYPEINFO{GlobalKeys} = ["function", ["list", "string"]]; }
sub GlobalKeys { return ShareKeys(shift, "global"); }

BEGIN{ $TYPEINFO{GlobalGetStr} = ["function", "string", "string", "string"]; }
sub GlobalGetStr { return ShareGetStr(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalSetStr} = ["function", "boolean", "string", "string"]; }
sub GlobalSetStr { return ShareSetStr(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalGetTruth} = ["function", "boolean", "string", "boolean"]; }
sub GlobalGetTruth { return ShareGetTruth(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalSetTruth} = ["function", "boolean", "string", "boolean"]; }
sub GlobalSetTruth { return ShareSetTruth(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalGetInteger} = ["function", "integer", "string", "integer"]; }
sub GlobalGetInteger { return ShareGetInteger(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalSetInteger} = ["function", "boolean", "string", "integer"]; }
sub GlobalSetInteger { return ShareSetInteger(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalEnable} = ["function", "boolean"]; }
sub GlobalEnable { ShareEnable(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalDisable} = ["function", "boolean"]; }
sub GlobalDisable { return ShareDisable(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalAdjust} = ["function", "boolean", "boolean"]; }
sub GlobalAdjust { return ShareAdjust(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalEnabled} = ["function", "boolean"]; }
sub GlobalEnabled { return ShareEnabled(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalSetMap} = ["function", "boolean", ["map", "string", "string"]]; }
sub GlobalSetMap { return ShareSetMap(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalUpdateMap} = ["function", "boolean", ["map", "string", "string"]]; }
sub GlobalUpdateMap { return ShareUpdateMap(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalGetMap} = ["function", ["map", "string", "string"]]; }
sub GlobalGetMap { return ShareGetMap(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalSetModified} = ["function", "void"]; }
sub GlobalSetModified { return ShareSetModified(shift, "global", @_); }

BEGIN{ $TYPEINFO{GlobalGetModified} = ["function", "boolean"]; }
sub GlobalGetModified { return ShareGetModified(shift, "global", @_); }


1;
