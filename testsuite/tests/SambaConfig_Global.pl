#!/usr/bin/perl

use SambaConfig;
use Data::Dumper;

# test Configured
print Dumper(SambaConfig->Configured());
SambaConfig->Import({a=>{b=>"x"}});
print Dumper(SambaConfig->Configured());

# test Get/Set Modified
print Dumper(SambaConfig->GetModified());
SambaConfig->SetModified();
print Dumper(SambaConfig->GetModified());

# test GetShares
print Dumper(SambaConfig->GetShares());



