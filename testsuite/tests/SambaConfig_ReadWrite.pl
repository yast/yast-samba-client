#!/usr/bin/perl

use SambaConfig;
use Data::Dumper;

$smb_conf = "/etc/samba/smb.conf";
$smb_conf_bak = "/tmp/smb.conf";
die "no permision to write to $smb_conf" unless -w $smb_conf;

# backup smb.conf
if ( -f $smb_conf && not -f $smb_conf_bak ) {
    open(SMB, "<", $smb_conf) or die $!;
    open(BAK, ">", $smb_conf_bak) or die $!;
    print BAK <SMB>;
    close BAK; close SMB;
}
# truncate smb.conf
open(SMB, ">", $smb_conf) or die $!; close SMB;

# no write
SambaConfig->Import({
    a      => {b=>"y"},
    home   => {path=>"/dev", _modified=>1},
    global => {x=>"y"}});
SambaConfig->Write();
SambaConfig->Import();
SambaConfig->Read();
SambaConfig->Dump();

# normal write
SambaConfig->Import({
    a      => {b=>"y", _modified=>1},
    home   => {path=>"/dev", _modified=>1},
    global => {_modified=>1, abc=>"ABC"}});
SambaConfig->ShareRemove("home");
SambaConfig->Write();
SambaConfig->Import();
SambaConfig->Read();
SambaConfig->Dump();

# write disabled share
SambaConfig->Import({
    a      => {b=>undef, c=>"z", _modified=>1, _disabled=>1}, 
    global => {_modified=>1, abc=>undef, def=>"DEF"}});
SambaConfig->Write();
SambaConfig->Import();
SambaConfig->Read();
SambaConfig->Dump();

# write (force) share with comment
SambaConfig->Import({
    a      => {c=>"q",_disabled=>1,_comment=>"share disabled by gizo"},
    _my    => {my=>1},
    global => {ghc=>"GHC"}});
SambaConfig->Write(1);
SambaConfig->Import();
SambaConfig->Read();
SambaConfig->Dump();

# restore smb.conf
open(SMB, ">", $smb_conf) or die $!;
open(BAK, "<", $smb_conf_bak) or die $!;
print SMB <BAK>;
close BAK; close SMB;


