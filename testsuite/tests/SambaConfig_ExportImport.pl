#!/usr/bin/perl

use strict;

use SambaConfig;
use Data::Dumper;

## test Get/Set Modified
SambaConfig->Import({
    a=>{"Bee Bee"=>"x", _modified=>1, _disabled=>1, _xxx=>8, _comment=>"A"},
    _internal=>{abc=>"ABC"},
    removed=>undef,
    b=>{no=>undef, "Two Two"=>22}});
SambaConfig->Dump("dump1: ");

my $dump = SambaConfig->Export();
#print Dumper($dump);

SambaConfig->Import($dump);
SambaConfig->Dump("dump2: ");
