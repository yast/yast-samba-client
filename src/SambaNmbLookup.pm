# File:   	modules/SambaNmbLookup.pm
# Package:	Configuration of samba-client
# Summary:	Data for configuration of samba-client, input and output functions.
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#		Martin Lazar <mlazar@suse.cz>
#
# $Id$
#
# Representation of the configuration of samba-client.
# Input and output routines. 

package SambaNmbLookup;

use strict;
use Data::Dumper;

use YaST::YCP qw(:DATA :LOGGING);
use YaPI;

textdomain "samba-client";
our %TYPEINFO;

YaST::YCP::Import("SCR");
YaST::YCP::Import("Service");
YaST::YCP::Import("PackageSystem");

use constant {
    # Path to the nmbstatus binary
    NMBSTATUS_EXE => "/usr/bin/nmbstatus",

    TRUE => 1,
    FALSE => 0,
};


# is nmbstatus still running?
my $Nmbstatus_running;

# nmbstatus output
my %Nmbstatus_output;

my $Nmbstatus_available;

# Flag, if we should restart nmbd after finishing nmbstatus.
# nmbd must be stopped, when doing nmbstatus, otherwise only
# local host is shown.
my $Nmbd_was_running;

# Start nmbstatus in background
# @return true on success
BEGIN{$TYPEINFO{Start}=["function","boolean"]}
sub Start {
    my ($self) = @_;

    if (!PackageSystem->Installed("samba-client")) {
	y2error("package samba-client not installed");
	return FALSE;
    }

    # first, check if nmbd is running
    if (PackageSystem->Installed("samba") && Service->Status("nmb")==0) {
        $Nmbd_was_running = 1;
        y2debug("Stopping nmbd for nmbstatus");
        # FIXME: we should check, if stop did not fail
        Service->Stop("nmb");
    }
    
    # start nmbstatus
    my $out = SCR->Execute(".target.bash_output", "/usr/bin/id --user");
    if ($out && $out->{stdout} == 0) {
	$Nmbstatus_running = SCR->Execute(".background.run_output", "su nobody -c " . NMBSTATUS_EXE);
    } else {
	$Nmbstatus_running = SCR->Execute(".background.run_output", NMBSTATUS_EXE);
    }
    if(!$Nmbstatus_running) {
        y2error("Cannot start nmbstatus");
        $Nmbstatus_available = 0;
        # restore nmbd
        if ($Nmbd_was_running) {
	    y2debug("Restarting nmbd for nmbstatus");
	    Service->Start("nmb");
	    $Nmbd_was_running = 0;
	}
	return FALSE;
    }
    
    return TRUE;
}

# Ensure that nmbstatus already finished. Then parse its output into nmbstatus_output
sub checkNmbstatus {
    if ($Nmbstatus_running) {

	# better count slept time
	my $wait = 1200;
	
	while ($wait>0 && SCR->Read(".background.isrunning")) {
	    select undef, undef, undef, 0.1;
	    $wait = $wait - 1;
	}
	
	if (SCR->Read(".background.isrunning")) {
	    y2error("Something went wrong, nmbstatus didn't finish in more that 2 minutes");
	    # better kill it
	    SCR->Execute(".background.kill");
	    $Nmbstatus_running = 0;
	    %Nmbstatus_output = ();
	    $Nmbstatus_available = 0;
	    return;
	}
	
	# nmbstatus already finished, parse the output
	my $output = SCR->Read(".background.newout");
	y2debug("nmbstatus => ".Dumper($output));
	
	$Nmbstatus_available = 1;
	$Nmbstatus_running = 0;
	%Nmbstatus_output = ();
	
	my $current_group = "";
	foreach (@$output) {
	    next unless /^([^\t]+)\t(.+)$/;
	    if ($1 eq "WORKGROUP") {
		$current_group = uc $2;
		$Nmbstatus_output{$current_group} = {};
	    } else {
		$Nmbstatus_output{$current_group}{uc $1} = uc $2;
	    }
	}
	
	# restore nmbd
	if ($Nmbd_was_running) {
	    y2debug("Restarting nmbd for nmbstatus");
	    Service->Start("nmb");
	    $Nmbd_was_running = 0;
	}
    }
}

# Return available flag of nmbstatus.
# @return boolean	true if nmbstatus is available
BEGIN{$TYPEINFO{Available}=["function","boolean"]}
sub Available {
    return $Nmbstatus_available;
}


# Check if a given workgroup is a domain or not. Tests presence of PDC or BDC in the workgroup.
#
# @param workgroup	the name of a workgroup to be tested
# @return boolean	true if the workgroup is a domain
BEGIN{$TYPEINFO{IsDomain}=["function","boolean","string"]}
sub IsDomain {
    my ($self, $workgroup) = @_;
    
    # ensure the data are up-to-date
    checkNmbstatus();

    return FALSE unless $Nmbstatus_output{uc $workgroup};
    
    # if there is PDC, return success
    return TRUE if $Nmbstatus_output{uc $workgroup}{PDC};
    
    # if PDC not found, try BDC
    return TRUE if $Nmbstatus_output{uc $workgroup}{BDC};

    # a different error happened
    return FALSE;
}

# Check if a given workgroup is a PDC or not.
#
# @param workgroup	the name of a workgroup to be tested
# @return boolean	true if the workgroup is a domain
BEGIN{$TYPEINFO{HasPDC}=["function","boolean","string"]}
sub HasPDC {
    my ($self, $workgroup) = @_;
    
    # ensure the data are up-to-date
    checkNmbstatus();

    return FALSE unless $Nmbstatus_output{uc $workgroup};
    
    # if there is PDC, return success
    return TRUE if $Nmbstatus_output{uc $workgroup}{PDC};
    
    # a different error happened
    return FALSE;
}

# Check if a given workgroup is a BDC or not.
#
# @param workgroup	the name of a workgroup to be tested
# @return boolean	true if the workgroup is a domain
BEGIN{$TYPEINFO{HasBDC}=["function","boolean","string"]}
sub HasBDC {
    my ($self, $workgroup) = @_;
    
    # ensure the data are up-to-date
    checkNmbstatus();

    return FALSE unless $Nmbstatus_output{uc $workgroup};
    
    # if there is BDC, return success
    return TRUE if $Nmbstatus_output{uc $workgroup}{BDC};
    
    # a different error happened
    return FALSE;
}

# Return a list of workgroups and domains already existing in the lan.
# @return list<string>  of found workgroups/domains
BEGIN{$TYPEINFO{GetAvailableNeighbours}=["function",["list", "string"], "string"]}
sub GetAvailableNeighbours {
    my ($self, $domain_suffix) = @_;
    $domain_suffix = "" unless $domain_suffix;
    
    checkNmbstatus();

    # TODO: inform user about problems
    return [ map {$_ . ($self->IsDomain($_)?$domain_suffix:"")} keys %Nmbstatus_output ];
}

# Return a list of domains already existing in the lan.
# @return list<string>  of found workgroups/domains
BEGIN{$TYPEINFO{GetAvailableDomains}=["function",["list", "string"]]}
sub GetAvailableDomains {
    my ($self) = @_;
    
    checkNmbstatus();

    # TODO: inform user about problems
    return [ grep {$self->IsDomain($_)} keys %Nmbstatus_output ];
}


8;
