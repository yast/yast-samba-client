# File:		modules/SambaWinbind.pm
# Package:	Configuration of samba-client
# Summary:	Data for configuration of samba-client, input and output functions.
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#		Martin Lazar <mlazar@suse.cz>
#
# $Id$

package SambaWinbind;

use strict;
use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

BEGIN{
YaST::YCP::Import("Nsswitch");
YaST::YCP::Import("Pam");
YaST::YCP::Import("PackageSystem");
YaST::YCP::Import("Progress");
YaST::YCP::Import("Service");
YaST::YCP::Import("SCR");

YaST::YCP::Import("SambaConfig");
}

use constant {
    TRUE => 1,
    FALSE => 0,
};


# Check windbind service status
# @return true if enabled, false if disabled, undef if not installed
BEGIN{$TYPEINFO{IsEnabled}=["function","boolean"]}
sub IsEnabled {
    my ($self) = @_;
    if (PackageSystem->Installed("samba-winbind")) {
        return Service->Enabled("winbind");
    }
    return FALSE;
}


# Change samba configuration file (/etc/samba/smb.conf)
#
# @param status a new status
BEGIN{$TYPEINFO{AdjustSambaConfig}=["function","void","boolean"]}
sub AdjustSambaConfig {
    my ($self, $status) = @_;
    if ($status) {
	# if turning on and there is no values set, use default
	SambaConfig->GlobalUpdateMap({
	    "idmap uid" => "10000-20000",
	    "idmap gid" => "10000-20000"
	});
	SambaConfig->GlobalSetStr ("template shell", "/bin/bash");
    }
    else {
	SambaConfig->GlobalSetStr ("template shell", undef);
    }
}


# Change nsswitch configuration.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
# @param if services should not be altered
# @return boolean true on succed
BEGIN{$TYPEINFO{AdjustNsswitch}=["function","boolean","boolean","boolean"]}
sub AdjustNsswitch {
    my ($self, $on, $write_only) = @_;

    foreach my $db ("passwd", "group") {
	my $nsswitch = Nsswitch->ReadDb($db);
	if ($on) {
	    push @$nsswitch, "winbind" unless grep {$_ eq "winbind"} @$nsswitch;
	} else {
	    @$nsswitch = grep {$_ ne "winbind"} @$nsswitch;
	}
	y2debug("Nsswitch->WriteDB($db, ".Dumper($nsswitch).")");
	Nsswitch->WriteDb($db, $nsswitch);
    };
    my $ret = Nsswitch->Write();
    y2error("Nsswitch->Write() failed") if (!$ret);

    # remove the passwd and group cache for nscd
    if (!$write_only && PackageSystem->Installed ("nscd")) {
	SCR->Execute (".target.bash", "/usr/sbin/nscd -i passwd");
	SCR->Execute (".target.bash", "/usr/sbin/nscd -i group");
    }
    # restart zmd (#174589) FIXME this should be elsewhere
    if (!$write_only && PackageSystem->Installed ("zmd") &&
	Service->Status ("novell-zmd") == 0)
    {
	Service->RunInitScript ("novell-zmd", "try-restart");
    }
    return $ret;
}
    
# Change PAM configuration.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
BEGIN{$TYPEINFO{AdjustPam}=["function","boolean","boolean"]}
sub AdjustPam {
    my ($self, $on) = @_;

    return Pam->Set ("winbind", $on);
}


# Enable/disable winbindd services.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
# @return integer errorcode
BEGIN{$TYPEINFO{AdjustService}=["function","boolean","boolean"]}
sub AdjustService {
    my ($self, $on) = @_;
    my $installed = PackageSystem->Installed("samba-winbind");
    return TRUE if !$on && !$installed;	# return ok
    if ($on && !$installed) {
	y2debug("Try to enable winbind service, but samba-winbind isn't installed.");
	return FALSE;
    }
    
    # enable/disable winbind service
    return TRUE if Service->Adjust("winbind", $on ? "enable" : "disable");
    return FALSE;
}

# Start/Stop winbindd services now.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
# @return integer errorcode
BEGIN{$TYPEINFO{StartStopNow}=["function","boolean","boolean"]}
sub StartStopNow {
    my ($self, $on) = @_;
    my $installed = PackageSystem->Installed("samba-winbind");
    return TRUE if !$on && !$installed;	# return ok
    if ($on && !$installed) {
	y2debug("Try to enable winbind service, but samba-winbind isn't installed.");
	return FALSE;
    }
    
    # start/stop windbind daemon
    if ($on) {
	# start the server
	if (Service->Status("winbind")!=0) {
	    # the service does not run
	    Service->Start("winbind") or return FALSE;
	} else {
	    # the service is running, restart it
	    Service->Restart("winbind") or return FALSE;
	}
    } else {
	if (Service->Status("winbind")==0) {
	    # the service is running
	    Service->Stop("winbind") or return FALSE;
	}
    }

    return TRUE;
}

8;

