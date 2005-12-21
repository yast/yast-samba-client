#! /usr/bin/perl
# File:		modules/SambaAD.pm
# Package:	Configuration of samba-client
# Summary:	Manage AD issues for samba-client
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id: SambaNetJoin.pm 22266 2005-03-04 09:50:00Z mlazar $
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

use constant {
    TRUE => 1,
    FALSE => 0,
};


# Active Directory server
my $ads		= "";

# Kerberos realm for AD
my $realm	= "";


# Check if a given workgroup is a Active Directory domain and return the name
# of AD domain controler
#
# @param workgroup	the name of a workgroup to be tested
# @return string	non empty when ADS was found
BEGIN{$TYPEINFO{GetADS}=["function","string","string"]}
sub GetADS {

    my ($self, $workgroup) 	= @_;
    my $server			= "";
y2internal ("get ads: workgroup: $workgroup");
    
    if (Mode->config ()) {
	return "";
    }

    # use DNS for finding DC
    if (FileUtils->Exists ("/usr/bin/dig")) {

	my $out = SCR->Execute (".target.bash_output", "dig _ldap._tcp.pdc._msdcs.$workgroup +noall +answer +authority");
y2internal ("dig output: ", Dumper ($out));
	foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
	    
y2warning ("line: $line");
	    next if $server ne "";
    if ($line =~ m/$workgroup/) {
		$server		= (split (/[ \t]/, $line))[4] || ".";
		chop $server;
	    }
	}
y2internal ("server: $server");
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
y2internal ("winsserver: $winsserver");
		    }
		}
	    }
	}
y2internal ("winsserver: $winsserver");

	# unicast query using nmblookup
	if ($winsserver ne "") {
	    $out = SCR->Execute (".target.bash_output", "LANG=C nmblookup -R -U $winsserver $workgroup#1b");
y2internal ("nmblookup $winsserver $workgroup#1b output: ", Dumper ($out));
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
	my $out = SCR->Execute (".target.bash_output", "LANG=C net LOOKUP DC $workgroup");
y2internal ("net LOOKUP DC $workgroup: ", Dumper ($out));
	if ($out->{"exit"} eq 0) {
	    foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
		if ($line ne "" && $server eq "") {
		    $server	= $line;
		    chomp $server;
		}
	    }
	}
    }
    if ($server ne "") {
y2internal ("net ads lookup -S $server: ", Dumper (SCR->Execute (".target.bash_output", "net ads lookup -S $server"))); 
    }
    if ($server ne "" &&
	SCR->Execute (".target.bash", "net ads lookup -S $server") ne 0) {
	$server	= "";
    }
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

    my $out	= SCR->Execute (".target.bash_output", "net ads lookup -S $server | grep 'Pre-Win2k Domain' | cut -f 2");
y2internal ("net ads lookup -S $server: ", Dumper ($out));
    if ($out->{"exit"} ne 0 || $out->{"stdout"} eq "") {
	return $domain;
    }
    my $workgroup	= $out->{"stdout"};
    chomp $workgroup;
y2internal ("workgroup: $workgroup");

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

    my $out	= SCR->Execute (".target.bash_output", "net ads info -S $server | grep Realm | cut -f 2 -d ' '");
y2internal ("net ads info -S $server: ", Dumper ($out));
    if ($out->{"exit"} ne 0 || $out->{"stdout"} eq "") {
	return "";
    }
    my $ret	= $out->{"stdout"};
    chomp $ret;
y2internal ("realm: $ret");

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

# Change samba configuration file (/etc/samba/smb.conf)
#
# @param status a new status
BEGIN{$TYPEINFO{AdjustSambaConfig}=["function","void","boolean"]}
sub AdjustSambaConfig {
    my ($self, $status) = @_;
    if ($status) {
	my $workgroup	= SambaConfig->GlobalGetStr ("workgroup", "");
	# remove special AD values if AD is not used
	my $remove	= (($ads || "") eq "");
	SambaConfig->GlobalUpdateMap({
	    "security"			=> $remove ? undef : "ADS",
	    "realm"			=> $remove ? undef : $realm,
	    "template shell" 		=> $remove ? undef : "/bin/bash",
	    "template homedir"		=> $remove ? undef : "/home/%D/%U",
	    "workgroup"			=> $remove ? undef : $workgroup,
	    "use kerberos keytab"	=> $remove ? undef : "Yes",
	    "pam_winbind:krb5_auth"	=> $remove ? undef : "yes",
	    "pam_winbind:krb5_ccache_type"
					=> $remove ? undef : "FILE",
	    "winbind refresh tickets"	=> $remove ? undef : "yes"
	});
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
	    "use_kerberos"	=> FALSE
	},
	"kerberos_client"	=> {
	    "default_realm"	=> $realm, 
	    "default_domain"	=> $domain,
	    "kdc_server"	=> $ads
	}
    });
    Kerberos->modified (TRUE);
    Kerberos->Write ();
    Progress->set ($prev);

    return TRUE;
}

42;
