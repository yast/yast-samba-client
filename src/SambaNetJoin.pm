#! /usr/bin/perl
# File:		modules/SambaNetJoin.pm
# Package:	Configuration of samba-server
# Summary:	Manage samba configuration data (smb.conf).
# Authors:	Martin Lazar <mlazar@suse.cz>
#
# $Id$
#

package SambaNetJoin;

use strict;
use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

YaST::YCP::Import("SCR");
YaST::YCP::Import("SambaConfig");
YaST::YCP::Import("SambaAD");

my %TestJoinCache;

# Check if this host is a member of a given domain.
#
# @param domain  a name of the domain to check
# @param force  do force check (otherwise use cache)
# @return boolean  true if the host is a member, false if not, nil on error (not possible to find out)
BEGIN{$TYPEINFO{Test}=["function","boolean","string"]}
sub Test {
    my ($self, $domain) = @_;
    
    return $TestJoinCache{$domain} if defined $TestJoinCache{$domain};

    my $protocol	= SambaAD->ADS () ne "" ? "ads" : "rpc";
    my $netbios_name 	= SambaConfig->GlobalGetStr("netbios name", undef);
    my $conf_file	= SCR->Read (".target.tmpdir")."/smb.conf";
    my $include		= "";
    $include	= "\n\tinclude = /etc/samba/dhcp.conf" if (SCR->Read (".sysconfig.network.dhcp.DHCLIENT_MODIFY_SMB_CONF") eq "yes");

    if ($protocol eq "ads") {
	my $realm	= SambaAD->Realm ();
	SCR->Write (".target.string", $conf_file, "[global]$include\n\trealm = $realm\n\tsecurity = ADS\n\tworkgroup = $domain\n");
    }
    else {
	SCR->Write (".target.string", $conf_file, "[global]$include\n\tsecurity = domain\n\tworkgroup = $domain\n");
    }

    # FIXME -P is probably wrong, but suppresses password prompt
    my $cmd = "LANG=C net $protocol testjoin -s $conf_file -P";
    if ($protocol ne "ads") {
	$cmd = $cmd." -w '$domain'" . ($netbios_name?" -n '$netbios_name'":"");
    }
    my $res = SCR->Execute(".target.bash_output", $cmd);
    y2internal("$cmd => ".Dumper($res));
    return $TestJoinCache{$domain} = ($res && defined $res->{exit} && $res->{exit}==0);
}

# Joins the host into a given domain. If user is provided, it will use
# the user and password for joining. If the user is nil, joining will
# be done anonymously.
#
# Attention: It will write the configuration for domain before settings the password
#
# @param domain	a name of a domain to be joined
# @param join_level	level of a domain membership when joining ("member", "bdc" or "pdc")
# @param user		username to be used for joining, or nil for anonymous
# @param passwd	password for the user
# @return string	an error message or nil if successful
BEGIN{$TYPEINFO{Join}=["function","string","string","string","string","string"]}
sub Join {
    my ($self, $domain, $join_level, $user, $passwd) = @_;
    
    my $netbios_name	= SambaConfig->GlobalGetStr("netbios name", undef);
    my $server		= SambaAD->ADS ();
    my $protocol	= $server ne "" ? "ads" : "rpc";
    my $tmpdir	= SCR->Read (".target.tmpdir");
    my $conf_file	= $tmpdir."/smb.conf";
    my $cmd		= "";

    my $include		= "";
    # bnc#520648 (DHCP may know WINS server address)
    $include	= "\n\tinclude = /etc/samba/dhcp.conf" if (SCR->Read (".sysconfig.network.dhcp.DHCLIENT_MODIFY_SMB_CONF") eq "yes");

    if ($protocol eq "ads") {
	my $krb_file	= $tmpdir."/krb5.conf";
	my $realm	= SambaAD->Realm ();
	SCR->Write (".target.string", $conf_file, "[global]$include\n\trealm = $realm\n\tsecurity = ADS\n\tworkgroup = $domain\n");
	$cmd		= "KRB5_CONFIG=$krb_file ";
	SCR->Write (".target.string", $krb_file, "[realms]\n\t$realm = {\n\tkdc = $server\n\t}\n");
    }
    else {
	SCR->Write (".target.string", $conf_file, "[global]$include\n\tsecurity = domain\n\tworkgroup = $domain\n");
    }

    $cmd = $cmd."net $protocol join "
	. ($protocol ne "ads" ? lc($join_level||"") : "")
	. ($protocol ne "ads" ? " -w '$domain'" : "")
	. " -s $conf_file"
	. (($protocol ne "ads" && $netbios_name)?" -n '$netbios_name'":"")
	. " -U '" . ($user||"") . "%" . ($passwd||"") . "'";

    my $result = SCR->Execute(".target.bash_output", $cmd);
    $cmd =~ s/(-U '[^%]*)%[^']*'/$1'/; # hide password in debug
    y2internal("$cmd => ".Dumper($result));
    
    # check the exit code, return nil on success
    if ($result && defined $result->{exit} && $result->{exit} == 0) {
	$TestJoinCache{$domain} = 1;
	return undef;
    }

    # otherwise return stderr
    $TestJoinCache{$domain} = undef;
    my $error = $result->{stdout} ne "" ? $result->{stdout} : $result->{stderr};
    return ($result && $error ne "") ? $error : "unknown error";
}

8;
