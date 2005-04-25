#!/usr/bin/perl

use SambaWinbind;
use lib "../src"; use SambaConfig;

use Data::Dumper;

## fake modules
sub PackageSystem::Installed {$installed{$_[1]}}
sub Service::Enabled {$service_enabled}
sub Service::Status {$service_status}
sub Service::Adjust {print "Service::Adjust($_[1], $_[2])\n"; $service_adjust_return}
sub Service::Start {print "Service::Start($_[1])\n"; $service_start_return}
sub Service::Stop {print "Service::Stop($_[1])\n"; $service_stop_return}
sub Service::Restart {print "Service::Restart($_[1])\n"; $service_restart_return}
sub Nsswitch::WriteDb {print "Nsswitch::WriteDB($_[1], [",join(",",@{$_[2]}),"])\n"}
sub Nsswitch::ReadDb {$nssdb{$_[1]}}
sub Nsswitch::Write {$write}
sub PamSettings::GetValues {$pamdb{$_[2]}}
sub PamSettings::SetValues {print "PamSettings::SetValues($_[1], $_[2], '", join(" ", @{$_[3]}),"')\n"}


## IsEnabled()
$installed{"samba-winbind"} = 0;
$service_enabled = 0;
print Dumper(!SambaWinbind->IsEnabled());

$installed{"samba-winbind"} = 1;
$service_enabled = 0;
print Dumper(!SambaWinbind->IsEnabled());

$installed{"samba-winbind"} = 1;
$service_enabled = 1;
print Dumper(SambaWinbind->IsEnabled());


## AdjustSambaConfig()
SambaWinbind->AdjustSambaConfig(0);
SambaConfig->Dump();

SambaWinbind->AdjustSambaConfig(1);
SambaConfig->Dump();


## Adjust Nsswitch()
%nssdb = (passwd => [qw(files winbind nis)], group => [qw(files ldap nis)]);
$write = 1;
SambaWinbind->AdjustNsswitch(0);

%nssdb = (passwd => [qw(files winbind nis)], group => [qw(files ldap nis)]);
$write = 0;
SambaWinbind->AdjustNsswitch(1);


## AdjustPam()
%pamdb = (auth => ["md5","call_modules=files,winbind,nis","nullok"], account => ["md5","call_modules=files,ldap,nis","nullok"]);
SambaWinbind->AdjustPam(0);

%pamdb = (auth => ["md5","call_modules=files,winbind,nis","nullok"], account => ["md5","call_modules=files,ldap,nis","nullok"]);
SambaWinbind->AdjustPam(1);

%pamdb = (auth => ["md5","nullok"], account => ["call_modules=winbind"]);
SambaWinbind->AdjustPam(0);

%pamdb = (auth => ["md5","nullok"], account => ["call_modules=winbind"]);
SambaWinbind->AdjustPam(1);

%pamdb = (auth => []);
SambaWinbind->AdjustPam(1);


## AdjustService()
%installed = ("samba-winbind" => 0);
print Dumper(SambaWinbind->AdjustService(0));

%installed = ("samba-winbind" => 0);
print Dumper(!SambaWinbind->AdjustService(1));

$service_adjust_return = 1;
%installed = ("samba-winbind" => 1);
print Dumper(SambaWinbind->AdjustService(1));

$service_adjust_return = 0;
%installed = ("samba-winbind" => 1);
print Dumper(!SambaWinbind->AdjustService(0));


## StartStopNow()
%installed = ("samba-winbind" => 0);
print Dumper(SambaWinbind->StartStopNow(0));

%installed = ("samba-winbind" => 0);
print Dumper(!SambaWinbind->StartStopNow(1));

%installed = ("samba-winbind" => 1);
$service_status = 1;
$service_start_return = 1;
print Dumper(SambaWinbind->StartStopNow(1));
$service_start_return = 0;
print Dumper(!SambaWinbind->StartStopNow(1));

%installed = ("samba-winbind" => 1);
$service_status = 0;
$service_restart_return = 1;
print Dumper(SambaWinbind->StartStopNow(1));
$service_restart_return = 0;
print Dumper(!SambaWinbind->StartStopNow(1));

%installed = ("samba-winbind" => 1);
$service_status = 0;
$service_stop_return = 1;
print Dumper(SambaWinbind->StartStopNow(0));
$service_stop_return = 0;
print Dumper(!SambaWinbind->StartStopNow(0));

%installed = ("samba-winbind" => 1);
$service_status = 1;
print Dumper(SambaWinbind->StartStopNow(0));
