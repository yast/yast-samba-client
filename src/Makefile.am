# Sources for samba-client

module_DATA = \
  modules/Samba.rb \
  modules/SambaNmbLookup.pm \
  modules/SambaConfig.pm \
  modules/SambaAD.pm \
  modules/SambaNetJoin.pm \
  modules/SambaWinbind.pm

client_DATA = \
  clients/samba-client_auto.rb \
  clients/samba-client.rb

yncludedir = @yncludedir@/samba-client
ynclude_DATA = \
  include/samba-client/wizards.rb \
  include/samba-client/dialogs.rb \
  include/samba-client/complex.rb \
  include/samba-client/routines.rb \
  include/samba-client/helps.rb

scrconf_DATA = \
  scrconf/cfg_smbconf.scr \
  scrconf/pam_mount.scr \
  scrconf/etc_security_winbind.scr

agent_SCRIPTS = \
  servers_non_y2/ag_pam_mount

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/samba-client.rnc

desktop_DATA = \
  desktop/samba-client.desktop

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(agent_SCRIPTS) $(schemafiles_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common