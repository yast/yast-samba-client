#!/usr/bin/perl

use Data::Dumper;

use SambaNmbLookup;

## test agent
use YaST::YCP qw(:DATA);
YaST::YCP::Import("Testsuite");
my $e_err = {target=>{bash_output=>{exit=>0, stdout=>8}}, background=>{run_output=>0, kill=>1}};
my $e_ok = {target=>{bash_output=>{exit=>0, stdout=>0}}, background=>{run_output=>1}};
my $r_running = {background=>{isrunning=>1}};
my $r_done = {background=>{isrunning=>0, newout=>[
    "WORKGROUP\tDEBIAN_FANS",
    "LMB\tGIZO",
    "MEMBERS\tGIZO",
    "",
    "WORKGROUP\tSUPERSONIC",
    "PDC\tSATYR",
    "DMB\tSATYR",
    "LMB\tSATYR",
    "MEMBERS\tSATYR",
    "",
    "WORKGROUP\tTEST",
    "BDC\tTEST",
]}};

## fake modules
sub PackageSystem::Installed {exists $installed{$_[1]} ? $installed{$_[1]} : 0};
sub Service::Status {exists $status{$_[1]} ? $status{$_[1]} : -1};


## Start()
%installed = ();
print Dumper(!SambaNmbLookup->Start());

%installed = ("samba-client" => 1);
Testsuite->Init([{},{},$e_ok],undef); # run as root, exec nbstatus return ok
print Dumper(SambaNmbLookup->Start());

%installed = ("samba-client" => 1, "samba" => 1);
Testsuite->Init([{},{},$e_err],undef); # run as user, exec nbstatus return err
print Dumper(!SambaNmbLookup->Start());

%installed = ("samba-client" => 1, "samba" => 1);
$status{"nmb"}=0; # nmb is running
print Dumper(!SambaNmbLookup->Start());

%installed = ("samba-client" => 1, "samba" => 1);
$status{"nmb"}=1; # nmb is stopped
print Dumper(!SambaNmbLookup->Start());


## nmbStatus()
$SambaNmbLookup::Nmbstatus_running=0;
SambaNmbLookup->checkNmbstatus(); # nmbstatus not running
print Dumper(SambaNmbLookup->GetAvailableNeighbours());

Testsuite->Init([$r_running,{},$e_err],undef); # background process is running
$SambaNmbLookup::Nmbstatus_running=1;
$SambaNmbLookup::wait = 0.4; # wait for 0.4 sec (instead of 120 sec)
SambaNmbLookup->checkNmbstatus();
print Dumper(SambaNmbLookup->GetAvailableNeighbours());

Testsuite->Init([$r_done,{},$e_ok],undef); # background process is finished
$SambaNmbLookup::Nmbstatus_running=1;
SambaNmbLookup->checkNmbstatus();
print Dumper(SambaNmbLookup->GetAvailableDomains());

Testsuite->Init([$r_done,{},$e_ok],undef); # background process is finished
$SambaNmbLookup::Nmbstatus_running=1;
$SambaNmbLookup::Nmbd_was_running=1;
SambaNmbLookup->checkNmbstatus();
print Dumper(SambaNmbLookup->GetAvailableNeighbours(" (domin)"));


## Query funcs()
print Dumper(SambaNmbLookup->Available());

print Dumper(
    !SambaNmbLookup->IsDomain("xxx"),
    SambaNmbLookup->IsDomain("SUPERSONIC"),
    SambaNmbLookup->IsDomain("TEST"),
    !SambaNmbLookup->IsDomain("GIZO"));

print Dumper(
    !SambaNmbLookup->HasPDC("xxx"),
    SambaNmbLookup->HasPDC("SUPERSONIC"),
    !SambaNmbLookup->HasPDC("TEST"),
    !SambaNmbLookup->HasPDC("GIZO"));

print Dumper(
    !SambaNmbLookup->HasBDC("xxx"),
    !SambaNmbLookup->HasBDC("SUPERSONIC"),
    SambaNmbLookup->HasBDC("TEST"),
    !SambaNmbLookup->HasBDC("GIZO"));
