#!/usr/bin/perl

use SambaNetJoin;
use lib "../src"; use SambaConfig;

use Data::Dumper;

## test agent
use YaST::YCP;
YaST::YCP::Import("Testsuite");
my $e_ok = {target=>{bash_output=>{exit=>0}}};
my $e_err = {target=>{bash_output=>{exit=>1, stdout=>"fake error"}}};

Testsuite->Init([{},{},$e_ok],undef);

print Dumper(
    SambaNetJoin->Test("xxx"),
    SambaNetJoin->Test("xxx"),
    !SambaNetJoin->Join("xxx"));

SambaConfig->GlobalSetStr("netbios name", "TUX");
Testsuite->Init([{},{},$e_err],undef);

print Dumper(
    !SambaNetJoin->Test("tux net"),
    SambaNetJoin->Join("tux net", "fake level", "user", "****") eq "fake error");
