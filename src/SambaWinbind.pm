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
YaST::YCP::Import("Service");
YaST::YCP::Import("Nsswitch");
YaST::YCP::Import("PamSettings");
YaST::YCP::Import("PackageSystem");

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
	    "idmap gid" => "10000-20000",
	});
#	SambaConfig::GlobalSetStr("security", "domain");
    }
}


# Change nsswitch configuration.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
# @return boolean true on succed
BEGIN{$TYPEINFO{AdjustNsswitch}=["function","boolean","boolean"]}
sub AdjustNsswitch {
    my ($self, $on) = @_;

    foreach my $db ("passwd", "group") {
	my %nsswitch_list = map {$_, 1} @{Nsswitch->ReadDb($db)};
        $nsswitch_list{"winbind"} = $on;
	my $list = [grep {$nsswitch_list{$_}} keys %nsswitch_list];
	y2debug("Nsswitch->WriteDB($db, ".Dumper($list).")");
	Nsswitch->WriteDb($db, $list);
    };

    return TRUE if Nsswitch->Write();
    y2error("Nsswitch->Write() fail");
    return FALSE;
}
    
# Change PAM configuration.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
BEGIN{$TYPEINFO{AdjustPam}=["function","boolean","boolean"]}
sub AdjustPam {
    my ($self, $on) = @_;

    foreach my $db ("auth", "account") {
	my @call_modules = grep {s/^call_modules=//} @{PamSettings->GetValues("pam_unix2", $db)};
	y2debug("call_modules for $db is ".join(",",@call_modules));
      
	unless (@call_modules) {
	    if ($on) {
		# add the option
		PamSettings->AddValue("pam_unix2", $db, "call_modules=winbind") or return FALSE;
	    }
	    # do nothing for off
	} else {
	    # find out list of called modules
	    my %mods = map {$_, 1} split ",", $call_modules[0];
	    $mods{winbind} = $on;
	
	    # change the current value
	    PamSettings->RemoveValue("pam_unix2", $db, "call_modules=$call_modules[0]") or return FALSE;
	    my $mods = join ",", grep {$mods{$_}} keys %mods;
	    PamSettings->AddValue("pam_unix2", $db, "call_modules=$mods") or return FALSE if $mods;
	}
    }    

    return TRUE;
}


# Enable/disable winbindd services.
#
# @param on the status of the winbind to be configured (true=enabled, false=disabled)
# @return integer errorcode
BEGIN{$TYPEINFO{AdjustService}=["function","boolean","boolean"]}
sub AdjustService {
    my ($self, $on) = @_;
    my $installed = PackageSystem->Installed("samba-winbind");
    return 1 if !$on && !$installed;	# return ok
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

