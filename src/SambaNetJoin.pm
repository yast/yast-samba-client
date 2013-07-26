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

use YaST::YCP qw(:LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

YaST::YCP::Import("Package");
YaST::YCP::Import("SCR");
YaST::YCP::Import("SambaConfig");
YaST::YCP::Import("SambaAD");
YaST::YCP::Import("SambaWinbind");
YaST::YCP::Import("String");
YaST::YCP::Import("YaPI::NETWORK");

my %TestJoinCache;

use constant {
    TRUE => 1,
    FALSE => 0,
};

# if cluster cleanup is needed at the end
my $cleanup_needed      = FALSE;

my $cluster_present     = undef;

# if DNS should be adapted with AD server
my $adapt_dns           = FALSE;

# name of base resource
my $rsc_id            = "";

# name of clone resource
my $clone_id            = "";

# Helper function to execute crm binary (internal only, not part of API).
# Takes all arguments in one string. 
sub CRMCall {

    my $params  = shift;
    my $cmd     = "/usr/sbin/crm $params";

    # it would open interactive mode without params
    unless ($params) {
      y2error ("No parameters to crm provided, exiting...");
      return "";
    }
     
    my $res     = SCR->Execute(".target.bash_output", $cmd);

    y2milestone ("output of '$cmd': ".Dumper($res));

    return $res->{"stdout"} || "";
}

# Check the presence and state of cluster environment
# @param force  do force check (otherwise use latest state)
# @return true when cluster is present and configured
BEGIN{$TYPEINFO{ClusterPresent}=[
    "function", "boolean", "boolean"]}
sub ClusterPresent {

    my ($self, $force) = @_;

    return $cluster_present if (defined $cluster_present) && !$force;

    $cluster_present    = FALSE;

    # do we have cluster packages installed?
    unless (Package->InstalledAll (["ctdb", "crmsh", "pacemaker"])) {
      return FALSE;
    }

    if (SambaAD->IsDHCPClient (FALSE)) {
      y2milestone ("DHCP client found: checking if IP addresses are configured for CTDB traffic...");
      # Go through IP addresses and check if they are cofigured for CTDB (/etc/ctdb/nodes).
      # This is not a perfect solution, but as we cannot find out if IP is statically assigned by
      # DHCP server, we have at least a hint that current addresses seem to be configured correctly.
      # See bnc#811008
      my $nodes = SCR->Read (".target.string", "/etc/ctdb/nodes") || "";
      my $out   = SCR->Execute (".target.bash_output",
        "LANG=C /sbin/ifconfig | grep 'inet addr' | grep -v '127.0.0.1' | cut -d: -f2 | cut -d ' ' -f1");
      my $cluster_ip    = TRUE;
      foreach my $line (split (/\n/,$out->{"stdout"} || "")) {
        if ($nodes !~ /$line/) {
          y2warning ("IP address $line is not configured for CTDB");
          $cluster_ip   = FALSE;
        }
      }
      return FALSE unless $cluster_ip;
    }

    my $out     = SCR->Execute (".target.bash_output", "/usr/sbin/crm_mon -s");
    if ($out->{"exit"} != 0) {
      y2warning ("cluster not configured or not online");
      return FALSE;
    }

    # find out resource and clone ids, to do later crm operations with
    my $show    = CRMCall ("configure save -");
    if ($show =~ /primitive (\w+) ocf:heartbeat:CTDB/) {
      $rsc_id = $1;
      if ($show =~ /clone (.+) $rsc_id/) {
           $clone_id        = $1;
      }
    }

    $cluster_present    = TRUE;
    return TRUE;
}

# Handle the information if DNS should be adapted ($adapt_dns)
# @param new value - set the new value for $adapt_dns variable
# @return return current value
BEGIN{$TYPEINFO{SetAdaptDNS}=[
    "function", "boolean", "boolean"]}
sub SetAdaptDNS {

    my ($self, $adapt)  = @_;
    $adapt_dns          = $adapt;
    return $adapt_dns;
}

# Edit the file /etc/resolv.conf and set the nameserver to AD server
# Do this only when explicitely for AD configurations and when selected by user
# @return Network adpatation success (the return value of YaPI::NETWORK->Write)
BEGIN{$TYPEINFO{AdaptDNS}=[
    "function", ["map","string","any"]]}
sub AdaptDNS {

    my $server  = SambaAD->ADS ();

    return unless ($adapt_dns && $server);

    my $network         = YaPI::NETWORK->Read ();
    my $nameservers     = $network->{"dns"}{"nameservers"} || [];
    push @$nameservers, $server;
    $network->{"dns"}{"nameservers"}    = $nameservers;

    return YaPI::NETWORK->Write({ "dns" => $network->{"dns"} });
}



# Prepare CTDB (Clustered database for Samba) before joining AD domain (fate#312706)
# The process is documented at
# http://docserv.suse.de/documents/SLE-HA/SLE-ha-guide/single-html/#pro.ha.samba.config.join-ad
# CTDB has to be already configured before calling this function
#
# @param server AD server
# @return boolean true if preparation was successfull, false otherwise (also 
BEGIN{$TYPEINFO{PrepareCTDB}=[
    "function", "boolean", "string"]}
sub PrepareCTDB {
    
    my ($self, $server) = @_;
    my $ret             = TRUE;

    return FALSE unless $self->ClusterPresent (0);

    # 3. Run crm configure edit and search for the ctdb resource. Add the following line:
    # ctdb_manages_winbind="false"

    CRMCall ("resource param $rsc_id set ctdb_manages_winbind no");

    # 4. save winbind into  /etc/nsswitch.conf
    # 5. Restart the NSC daemon:
    SambaWinbind->AdjustNsswitch (TRUE, TRUE);

    # 6. Create the Kerberbos configuration file /etc/krb5.conf (the tmp one from Join is enough)
    # 7. Cleanup CTDB:
    CRMCall ("resource cleanup $clone_id");

    # 8. Wait until the unhealty status disappears.
    my $start   = time;
    my $wait    = 60; # 1 minute timeout

    while (time<$start+$wait) {
      my $out     = SCR->Execute(".target.bash_output", "/usr/bin/ctdb status");
      last if ($out->{"exit"} == 0);
      sleep (1); #0.5);
    }

    # additional cluster operations will be needed after join
    $cleanup_needed     = TRUE;

    return $ret;
}

# Adapt CTDB (Clustered database for Samba) after joining AD domain (fate#312706)
#
BEGIN{$TYPEINFO{CleanupCTDB}=["function", "boolean"]}
sub CleanupCTDB {

    my $self    = shift;

    return TRUE unless $cleanup_needed;

    # 10. Change the ctdb_manages_winbind option:

    # a. Stop the ctdb resource:
    CRMCall ("resource stop $clone_id");

    # b. Change the value from false to true: ctdb_manages_winbind="true"
    CRMCall ("resource param $rsc_id set ctdb_manages_winbind yes");

    # c. Restart the ctdb resource:
    CRMCall ("resource start $clone_id");

    $cleanup_needed     = FALSE;

    return TRUE;
}

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
	my $content     = "[global]$include\n\trealm = $realm\n\tsecurity = ADS\n\tworkgroup = $domain\n";
        if ($self->ClusterPresent (0)) {
            # ensure cluster related options are used from original file
            # bnc#809208
            my $clustering      = SambaConfig->GlobalGetStr ("clustering", undef);
            if (defined $clustering) {
              my $ctdbd_socket    = SambaConfig->GlobalGetStr ("ctdbd socket", "");
              $content .= "\t" . "clustering = $clustering" . "\n";
              $content .= "\t" . "ctdbd socket =$ctdbd_socket" . "\n";
            }
            else {
              y2warning ("'clustering' not defined in smb.conf");
              return FALSE;
            }
        }
	SCR->Write (".target.string", $conf_file, $content);
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
# @param passwd		password for the user
# @param machine	machine account to join into (fate 301320)
# @return string	an error message or nil if successful
BEGIN{$TYPEINFO{Join}=[
    "function","string","string","string","string","string","string"]}
sub Join {
    my ($self, $domain, $join_level, $user, $passwd, $machine) = @_;
    
    my $netbios_name	= SambaConfig->GlobalGetStr("netbios name", undef);
    my $server		= SambaAD->ADS ();
    my $protocol	= $server ne "" ? "ads" : "rpc";
    my $tmpdir	= SCR->Read (".target.tmpdir");
    my $conf_file	= $tmpdir."/smb.conf";
    my $cmd		= "";

    my $include		= "";
    # bnc#520648 (DHCP may know WINS server address)
    $include	= "\n\tinclude = /etc/samba/dhcp.conf" if (SCR->Read (".sysconfig.network.dhcp.DHCLIENT_MODIFY_SMB_CONF") eq "yes");

    AdaptDNS ();

    if ($protocol eq "ads") {

	$self->PrepareCTDB ($server);

	my $krb_file	= $tmpdir."/krb5.conf";
	my $realm	= SambaAD->Realm ();
	my $content     = "[global]$include\n\trealm = $realm\n\tsecurity = ADS\n\tworkgroup = $domain\n";
	my $kerberos_method	= SambaConfig->GlobalGetStr ("kerberos method", "");
	if ($kerberos_method) {
	    $content	= $content."\tkerberos method = $kerberos_method\n";
	}
        if ($self->ClusterPresent (0)) {
            # ensure cluster related options are used from original file
            # bnc#809208
            my $clustering      = SambaConfig->GlobalGetStr ("clustering", undef);
            if (defined $clustering) {
              my $ctdbd_socket    = SambaConfig->GlobalGetStr ("ctdbd socket", "");
              $content .= "\t" . "clustering = $clustering" . "\n";
              $content .= "\t" . "ctdbd socket =$ctdbd_socket" . "\n";
            }
            else {
              y2error ("'clustering' not defined in smb.conf, canceling join attempt");
              return __("Unable to proceed with join: Inconsistent cluster state");
            }
        }
	SCR->Write (".target.string", $conf_file, $content);
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
#	. (($protocol ne "ads" && $netbios_name)?" -n '$netbios_name'":"")
# FIXME check if netbios name can be used with AD
	. ($netbios_name  ? " -n '$netbios_name'" : "")
	. " -U '" . String->Quote ($user) . "%" . String->Quote ($passwd) . "'";

    if ($machine) {
	$machine	=~ s/dc=([^,]*)//gi; # remove DC=* parts
	$machine	=~ s/([^,]*)=//gi; # leave only values from the rest
	my $m		= join ('/', reverse (split (/,/,$machine)));	
	$cmd		= $cmd. " createcomputer=\"$m\"" if $m;
    }

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

# Leave given domain.
#
# @param domain	a name of a domain to be left
# @param user		username to be used for joining, or nil for anonymous
# @param passwd		password for the user
# @return string	an error message or nil if successful
BEGIN{$TYPEINFO{Leave}= [ "function","string","string","string","string"]}
sub Leave {

    my ($self, $domain, $user, $passwd) = @_;
    
    my $tmpdir		= SCR->Read (".target.tmpdir");
    my $realm		= SambaAD->Realm ();
    
    my $cmd = "net ads leave -U '"
	. String->Quote ($user) . "%" . String->Quote ($passwd) . "'";

    my $result = SCR->Execute(".target.bash_output", $cmd);
    $cmd =~ s/(-U '[^%]*)%[^']*'/$1'/; # hide password in the log
    y2internal("$cmd => ".Dumper($result));
    
    # check the exit code, return nil on success
    if ($result && defined $result->{exit} && $result->{exit} == 0) {
	# force new testjoin run (maybe domain from first testjoin was replaced
	# by realm => empty whole hash)
	%TestJoinCache	= ();
	return undef;
    }

    # otherwise return stderr
    my $error = $result->{stdout} ne "" ? $result->{stdout} : $result->{stderr};
    return ($result && $error ne "") ? $error : "unknown error";
}


8;
