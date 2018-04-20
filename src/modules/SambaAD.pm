#! /usr/bin/perl
# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:		modules/SambaAD.pm
# Package:	Configuration of samba-client
# Summary:	Manage AD issues for samba-client
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
#

package SambaAD;

use strict;
use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

YaST::YCP::Import ("FileUtils");
YaST::YCP::Import ("Kerberos");
YaST::YCP::Import ("Mode");
YaST::YCP::Import ("SCR");
YaST::YCP::Import ("SambaConfig");
YaST::YCP::Import ("YaPI::NETWORK");

use constant {
    TRUE => 1,
    FALSE => 0,
};

# create a dummy smb.conf file only for performing the libnet commands
my $dummy_conf_file = SCR->Read (".target.tmpdir") . "/dummy-smb.conf";
SCR->Write (".target.string", $dummy_conf_file, "");

# Active Directory server
my $ads		= "";

# Kerberos realm for AD
my $realm	= "";

# remember if machine is DHCP client
my $dhcp_client         = undef;

# Checks if machine is DHCP client
# @param force  do force check (otherwise use latest state)
BEGIN{$TYPEINFO{IsDHCPClient}=["function","boolean", "boolean"]}
sub IsDHCPClient {

    my ($self, $force) = @_;

    return $dhcp_client if (defined $dhcp_client) && !$force;

    my $network         = YaPI::NETWORK->Read ();
    $dhcp_client        = TRUE;
    foreach my $iface (values %{$network->{"interfaces"}}) {
      $dhcp_client      = $dhcp_client && (($iface->{"bootproto"} || "") =~ m/^dhcp[46]?$/);
    }
    return $dhcp_client;
}

# Read the list of available machine accounts in the current domain
#
# @param domain		AD domain
# @param user		user name
# @param password	password
# @return list
BEGIN{$TYPEINFO{GetMachines}= [
    "function", ["list","string"], "string", "string", "string"]}
sub GetMachines {

    my ($self, $domain, $user, $passwd) = @_;
    my @ret			= ();
    
    my $tmpdir		= SCR->Read (".target.tmpdir");
    my $conf_file	= $tmpdir."/smb.conf";
    my $krb_file	= $tmpdir."/krb5.conf";
    my $cmd		= "KRB5_CONFIG=$krb_file net ads search \"(objectclass=organizationalUnit)\" distinguishedName -s $conf_file -U '$user%". ($passwd||"") . "'";

    SCR->Write (".target.string", $krb_file, "[realms]\n\t$realm = {\n\tkdc = $ads\n\t}\n");
    SCR->Write (".target.string", $conf_file, "[global]\n\trealm = $realm\n\tsecurity = ADS\n\tworkgroup = $domain\n");

    my $result = SCR->Execute(".target.bash_output", $cmd);
    if ($result->{"exit"} eq 0) {
	foreach my $line (split (/\n/,$result->{"stdout"} || "")) {
	    if ($line =~ m/^distinguishedName:/) {
		my $dn	= $line;
		$dn	=~ s/^distinguishedName:([\t ]*)//g;
		push @ret, $dn if $dn;
	    }
	}
    }
    else {
	$cmd =~ s/(-U '[^%]*)%[^']*'/$1'/; # hide password in the log
	y2warning ("$cmd failed: ".Dumper($result));
	return undef;
    }
    return \@ret;
}

# Check if a given workgroup is a Active Directory domain and return the name
# of AD domain controler
#
# @param workgroup	the name of a workgroup to be tested
# @return string	non empty when ADS was found
BEGIN{$TYPEINFO{GetADS}=["function","string","string"]}
sub GetADS {

    my ($self, $workgroup) 	= @_;
    my $server			= "";

    y2milestone ("get ads: workgroup: $workgroup");
    
    if (Mode->config ()) {
	return "";
    }

    # use DNS for finding DC
    if (FileUtils->Exists ("/usr/bin/dig")) {

	# we have to select server from correct site - see bug #238249.
	# TODO use +short instead?
	my $out = SCR->Execute (".target.bash_output", "dig -t srv _ldap._tcp.dc._msdcs.$workgroup +noall +answer");
	y2debug ("dig output: ", Dumper ($out));
	my $tmpserver	= "";
	my @sites	= ();
	foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
	    
	    y2debug ("line: $line");
	    next if $server ne "";
	    if ($line =~ m/$workgroup/ && $line !~ m/^;/) {
		$tmpserver   = "";
		$tmpserver	= (split (/[ \t]/, $line))[7] || ".";
		chop $tmpserver;
	    }
	    if ($tmpserver) {
		my $cmd	= "LANG=C net -s $dummy_conf_file ads lookup -S $tmpserver";
		$out	= SCR->Execute (".target.bash_output", $cmd);
		if ($out->{"exit"} eq 0) {
		    foreach my $l (split (/\n/,$out->{"stdout"} || "")) {
			next if $server;
			$server = $tmpserver if ($l =~ m/Is the closest DC/ && $l =~ m/yes/);
			if ($l =~ m/Client Site Name/ && $l !~ m/Default-First-Site-Name/) {
			    my $site	= $l;
			    $site	=~ s/^Client Site Name:([\t ]*)//g;
			}
		    }
		}
	    }
	}
	y2debug ("server: $server");
	# there were no sites not "closest DC" -> take the only one result
	if (!$server && $tmpserver && not @sites) {
	    $server	= $tmpserver;
	}
	# we still don't know which server to choose, but we know list of sites
        elsif ($server eq "" && @sites) {
	    foreach my $site (@sites) {
		next if $server;
		$out	= SCR->Execute (".target.bash_output", "dig -t _ldap._tcp.$site._sites.dc._msdcs.$workgroup +noall +answer");
		y2debug ("dig output: ", Dumper ($out));
		if ($out->{"exit"} eq 0) {
		    foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
			next if $server;
			if ($line =~ m/$workgroup/ && $line !~ m/^;/) {
			    $server      = (split (/[ \t]/, $line))[7] || ".";
			    chop $server;
			}
		    }
		}
	    }
	}
	y2debug ("server: $server");
    }
    
    # no success => try NETBIOS name resolution
    if ($server eq "") {

	# check for WINSSERVER in /var/lib/dhcpcd/dhcpcd-$IFNAME.info
	my $winsserver	= "";
	my $out	= SCR->Execute
	    (".target.bash_output","LANG=C ls /var/lib/dhcpcd/dhcpcd-*.info");
	if ($out->{"exit"} eq 0) {
	    foreach my $path (split (/\n/,$out->{"stdout"} || "")) {
		next if $winsserver ne "";
		my $file = SCR->Read (".target.string", $path);
		foreach my $line (split (/\n/, $file)) {
		    if ($line =~ m/^WINSSERVER=/) {
			$winsserver	= $line;
			$winsserver	=~ s/^WINSSERVER=//g;
			y2milestone ("winsserver: $winsserver");
		    }
		}
	    }
	}
	y2debug ("winsserver: $winsserver");

	# unicast query using nmblookup
	if ($winsserver ne "") {
	    $out = SCR->Execute (".target.bash_output", "LANG=C nmblookup -R -U $winsserver $workgroup#1b");
	    y2debug("nmblookup $winsserver $workgroup#1b output:",Dumper($out));
	    foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
		next if $server ne "";
		next if $line =~ m/querying/;
		next if $line =~ m/failed/;
		if ($line =~ m/$workgroup/) {
		    my @parts	= split (/[ \t]/, $line);
		    $server	= $parts[0] || "";
		}
	    }
	}
    }
    if ($server eq "") {
	my $out = SCR->Execute (".target.bash_output", "LANG=C net -s $dummy_conf_file LOOKUP DC $workgroup");
	y2debug ("net LOOKUP DC $workgroup: ", Dumper ($out));
	if ($out->{"exit"} eq 0) {
	    foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
		if ($line ne "" && $server eq "") {
		    $server	= $line;
		    chomp $server;
		}
	    }
	}
    }
    if ($server ne "" &&
	SCR->Execute (".target.bash", "net -s $dummy_conf_file ads lookup -U% -S $server") ne 0) {
	$server	= "";
    }
    y2milestone ("returning server: $server");
    return $server;
}

# Check if a given workgroup is a Active Directory domain and set the
# name of AD domain controler to global variable
#
# @param workgroup	the name of a workgroup to be tested
# @return string	non empty when ADS was found
BEGIN{$TYPEINFO{ReadADS}=["function","string","string"]}
sub ReadADS {

    my ($self, $workgroup) 	= @_;
    $ads			= $self->GetADS ($workgroup);
    return $ads;
}

# return the value of $ads
BEGIN{$TYPEINFO{ADS}=["function","string"]}
sub ADS {
    return $ads;
}

# Set the value of $ads
# return true if the new value is different from the previous one
BEGIN{$TYPEINFO{SetADS}=["function","boolean", "string"]}
sub SetADS {

    my ($self, $new_ads) 	= @_;
    if ($new_ads eq $ads) {
	return FALSE;
    }
    $ads = $new_ads;
    return TRUE;
}

    

# Get AD Domain name and return the name of work group ("Pre-Win2k Domain")
# @param domain	the domain user entered
# @param server AD server (used for querying)
# @return	workgroup (returns domain if anything fails)
BEGIN{$TYPEINFO{ADDomain2Workgroup}=["function","string","string", "string"]}
sub ADDomain2Workgroup {

    my ($self, $domain, $server) = @_;


    return "" if $server eq "";

    my $out	= SCR->Execute (".target.bash_output", "net -s $dummy_conf_file ads lookup -S $server | grep 'Pre-Win2k Domain' | awk '{print \$3}'");

    y2debug ("net ads lookup -S $server: ", Dumper ($out));
    if ($out->{"exit"} ne 0 || $out->{"stdout"} eq "") {
	return $domain;
    }
    my $workgroup	= $out->{"stdout"};
    chomp $workgroup;
    y2milestone ("workgroup: $workgroup");
    return $workgroup;
}

# Return the value of AD work group ("Pre-Win2k Domain") for the current ADS
# @param domain	the domain user entered
# @return	workgroup (returns domain if anything fails)
BEGIN{$TYPEINFO{GetWorkgroup}=["function","string","string"]}
sub GetWorkgroup {

    my ($self, $domain)	= @_;
    return $self->ADDomain2Workgroup ($domain, $ads);
}


# Get the Kerberos realm for given AD DC
# @server	AD domain controler
# @return	the realm for Kerberos configuration; empty if none is available
BEGIN{$TYPEINFO{GetRealm}=["function","string", "string"]}
sub GetRealm {

    my ($self, $server) = @_;

    return "" if $server eq "";

    my $out	= SCR->Execute (".target.bash_output", "net -s $dummy_conf_file ads info -S $server | grep Realm | cut -f 2 -d ' '");
    
    y2debug ("net ads info -S $server: ", Dumper ($out));

    if ($out->{"exit"} ne 0 || $out->{"stdout"} eq "") {
	return "";
    }
    my $ret	= $out->{"stdout"};
    chomp $ret;
    y2milestone ("realm: $ret");
    return $ret;
}

# Read the Kerberos realm for current AD DC and set it to global variable
# @return       the realm for Kerberos configuration
BEGIN{$TYPEINFO{ReadRealm}=["function","string"]}
sub ReadRealm {

    my $self	= shift;
    $realm 	= $self->GetRealm ($ads);
    return $realm;
}

# return the value of $realm
BEGIN{$TYPEINFO{Realm}=["function","string"]}
sub Realm {
    return $realm;
}

# set the new value of realm
# return true if the new value is different from the previous one
BEGIN{$TYPEINFO{SetRealm}=["function","boolean","string"]}
sub SetRealm {
    my ($self, $new_realm) 	= @_;
    if ($new_realm eq $realm) {
	return FALSE;
    }
    $realm = $new_realm;
    return TRUE;
}


# Change samba configuration file (/etc/samba/smb.conf)
#
# @param status a new status
BEGIN{$TYPEINFO{AdjustSambaConfig}=["function","void","boolean"]}
sub AdjustSambaConfig {
    my ($self, $status) = @_;

    my $workgroup	= SambaConfig->GlobalGetStr ("workgroup", "");
    # remove special AD values if AD is not used
    my $remove	= (($ads || "") eq "");
    SambaConfig->GlobalSetMap({
	"security"			=> $remove ? "domain" : "ADS",
	"realm"				=> $remove ? undef : $realm,
	"template homedir"		=> $remove ? undef : "/home/%D/%U",
	"winbind refresh tickets"	=> $remove ? undef : "yes"
    });
    SambaConfig->WinbindGlobalSetMap({
	"krb5_auth"			=> $remove ? undef : "yes",
	"krb5_ccache_type"		=> $remove ? undef : "FILE"
    });
    if ($status) {
	if (SambaConfig->GlobalGetTruth ("domain logons", 0)) {
	    SambaConfig->GlobalSetTruth ("domain logons", 0)
	}
	if (SambaConfig->GlobalGetTruth ("domain master", 0)) {
	    SambaConfig->GlobalSetStr ("domain master", "Auto")
	}
    }
}

# Change Kerberos configuration (for AD). Uses current (previously read)
# value of ADS and Kerbers realm
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
BEGIN{$TYPEINFO{AdjustKerberos}=["function","boolean","boolean"]}
sub AdjustKerberos {

    my ($self, $on) = @_;
    if (!$on || ($ads || "") eq "") { 
	# check if it is AD domain
	# when disabling, we do not have to change this configuration
	return TRUE;
    }
    my $domain	= "\L$realm";

    my $prev	= Progress->set (FALSE);
    Kerberos->Read ();
    Kerberos->Import ({
	"pam_login"		=> {
	    "use_kerberos"	=> YaST::YCP::Boolean (0)
	},
	"kerberos_client"	=> {
	    "default_realm"	=> $realm, 
	    "default_domain"	=> $domain,
	    "kdc_server"	=> $ads,
	    "trusted_servers"	=> $ads
	}
    });
    Kerberos->dns_used (FALSE);
    Kerberos->modified (TRUE);
    Kerberos->Write ();
    Progress->set ($prev);

    return TRUE;
}

42;
