#!/usr/bin/perl

use SambaConfig;
use Data::Dumper;

# test general shares

SambaConfig->Import(
{
    a=>{x=>"y"}, 
    b=>{u=>"v", _internal=>"xxx", no=>undef},
    ro=>{"read only"=>"Yes", "root directory"=>"/root", int=>8},
    rw=>{"read only"=>"No", "root directory"=>"/dev/zero", _disabled=>1},
});

print Dumper("ShareRemove",
    !defined SambaConfig->ShareRemove(),
    SambaConfig->ShareRemove("a"),
    !SambaConfig->ShareRemove("a"));

print Dumper("ShareExists",
    !defined SambaConfig->ShareExists(),
    !SambaConfig->ShareExists("a"),
    SambaConfig->ShareExists("b"));

print Dumper("ShareKeys",
    !defined SambaConfig->ShareKeys(),
    $#{SambaConfig->ShareKeys("a")}==-1,
    $#{SambaConfig->ShareKeys("b")}==0);

print Dumper("ShareSetStr",
    !defined SambaConfig->ShareSetStr(),
    !defined SambaConfig->ShareSetStr("g"),
    SambaConfig->ShareSetStr("g","My Key", "My Val"),
    !SambaConfig->ShareSetStr("g","Lock Dir"),
    SambaConfig->ShareSetStr("g","Lock Dir", "/dev"),
    SambaConfig->ShareSetStr("g","Lock Dir", "/home"),
    !SambaConfig->ShareSetStr("g","Lock Dir", "/home"),
    SambaConfig->ShareSetStr("g","Lock Dir"),
    !SambaConfig->ShareSetStr("g","writable"),
    SambaConfig->ShareSetStr("g","writable", 1),
    !SambaConfig->ShareSetStr("g","writable", 1),
    SambaConfig->ShareSetStr("g","writable", 0),
    SambaConfig->ShareSetStr("g","writable"));

print Dumper("ShareGetKey",
    !defined SambaConfig->ShareGetStr(),
    !defined SambaConfig->ShareGetStr("g"),
    SambaConfig->ShareGetStr("ro","root","default") eq "/root",
    SambaConfig->ShareGetStr("rw","root","default") eq "/dev/zero",
    !defined SambaConfig->ShareGetStr("xx","root"),
    SambaConfig->ShareGetStr("xx","root","default") eq "default");

print Dumper("ShareGetTruth (+inverted synonyms)",
    !defined SambaConfig->ShareGetTruth(),
    !defined SambaConfig->ShareGetTruth("g"),
    !SambaConfig->ShareGetTruth("ro","writable"),
    SambaConfig->ShareGetTruth("rw","writable"),
    !defined SambaConfig->ShareGetTruth("xx","writable"),
    SambaConfig->ShareGetTruth("xx","writable", 1),
    SambaConfig->ShareGetTruth("ro","Read Only"),
    !SambaConfig->ShareGetTruth("rw","Read Only"),
    !SambaConfig->ShareGetTruth("xx","Read Only", 0));

print Dumper("ShareGetInt",
    !defined SambaConfig->ShareGetInteger(),
    !defined SambaConfig->ShareGetInteger("g"),
    SambaConfig->ShareGetInteger("ro","int") == 8,
    !defined SambaConfig->ShareGetInteger("rw","int"),
    SambaConfig->ShareGetInteger("rw","int", 9) == 9);

print Dumper("ShareSetInt, ShareSetTruth",
    !defined SambaConfig->ShareSetTruth(),
    !defined SambaConfig->ShareSetInteger("g"),
    !SambaConfig->ShareSetInteger("ro","int", 8),
    SambaConfig->ShareSetInteger("ro","int", 9),
    !SambaConfig->ShareSetTruth("rw","truth"),
    SambaConfig->ShareSetTruth("rw","truth", 1),
    SambaConfig->ShareSetTruth("rw","truth", 0));

print Dumper("Share Enable/Disable/Adjust/Enabled",
    !defined SambaConfig->ShareEnable(),
    !defined SambaConfig->ShareEnable("xxxxx"),
    !defined SambaConfig->ShareDisable(),
    !defined SambaConfig->ShareDisable("xxxxx"),
    !defined SambaConfig->ShareEnabled(),
    !defined SambaConfig->ShareEnabled("xxxxx"),
    !SambaConfig->ShareAdjust("ro", 1),
    !SambaConfig->ShareAdjust("rw", 0),
    SambaConfig->ShareAdjust("rw", 1),
    SambaConfig->ShareAdjust("ro", 0),
    SambaConfig->ShareEnabled("rw"),
    !SambaConfig->ShareEnabled("ro"));

print Dumper("Share Get/Set/Update Map",
    !defined SambaConfig->ShareGetMap(),
    !defined SambaConfig->ShareSetMap(),
    !defined SambaConfig->ShareUpdateMap(),
    SambaConfig->ShareSetMap("home", {a=>"ABC", x=>"XYZ"}),
    !SambaConfig->ShareSetMap("home", {a=>"ABC", x=>"XYZ"}),
    !SambaConfig->ShareUpdateMap("home", {x=>"123"}),
    SambaConfig->ShareUpdateMap("home", {y=>"123"}),
    length(%{SambaConfig->ShareGetMap("home")})==3);


print Dumper("Share Get/Set Modified",
    !defined SambaConfig->ShareGetModified(),
    !defined SambaConfig->ShareSetModified(),
    !SambaConfig->ShareGetModified("mod"),
    SambaConfig->ShareSetModified("mod"),
    !SambaConfig->ShareSetModified("mod"),
    SambaConfig->ShareGetModified("mod"));

print Dumper("Share Get/Set Comment",
    !defined SambaConfig->ShareGetComment(),
    !defined SambaConfig->ShareSetComment(),
    !defined SambaConfig->ShareGetComment("mod"),
    SambaConfig->ShareSetComment("mod","comment"),
    !SambaConfig->ShareSetComment("mod","comment"),
    SambaConfig->ShareGetComment("mod") eq "comment");
