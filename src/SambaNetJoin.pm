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

my %TestJoinCache;

# Check if this host is a member of a given domain.
#
# @param domain  a name of the domain to check
# @param force  do force check (otherwise use cache)
# @return boolean  true if the host is a member, false if not, nil on error (not possible to find out)
BEGIN{$TYPEINFO{Test}=["function","boolean","string"]}
sub Test {
    my ($self, $domain) = @_;
    # FIXME: ADS
    
    return $TestJoinCache{$domain} if defined $TestJoinCache{$domain};
    
    my $netbios_name = SambaConfig->GlobalGetStr("netbios name", undef);
    my $cmd = "LANG=C net rpc testjoin -s /dev/zero -w '$domain'" . ($netbios_name?" -n '$netbios_name'":"");
    my $res = SCR->Execute(".target.bash_output", $cmd);
    y2debug("$cmd => ".Dumper($res));
    return $TestJoinCache{$domain} = ($res && $res->{exit}==0);
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
    
    my $netbios_name = SambaConfig->GlobalGetStr("netbios name", undef);
    my $cmd = "net rpc join " . lc($join_level||"")
	. " -w '$domain' -s /dev/zero"
	. ($netbios_name?" -n '$netbios_name'":"")
	. " -U '" . ($user||"") . "%" . ($passwd||"") . "'";

    my $result = SCR->Execute(".target.bash_output", $cmd);
    $cmd =~ s/(-U '[^%]*)%[^']*'/$1'/; # hide password in debug
    y2debug("$cmd => ".Dumper($result));
    
    # check the exit code, return nil on success
    if ($result && $result->{exit} == 0) {
	$TestJoinCache{$domain} = 1;
	return undef;
    }

    # otherwise return stderr
    $TestJoinCache{$domain} = undef;
    return $result ? $result->{stdout} : "unknown error";
}

8;
