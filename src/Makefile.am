# Sources for samba-client

module_DATA = \
  modules/Kerberos.rb \
  modules/Samba.rb \
  modules/SambaNmbLookup.pm \
  modules/SambaConfig.pm \
  modules/SambaAD.pm \
  modules/SambaAPI.py \
  modules/SambaNetJoin.pm \
  modules/SambaNetUtils.rb \
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
  scrconf/etc_security_winbind.scr \
  scrconf/etc_ssh_ssh_config.scr

agent_SCRIPTS = \
  servers_non_y2/ag_pam_mount

schemafilesdir = $(schemadir)/autoyast/rnc
schemafiles_DATA = \
  autoyast-rnc/samba-client.rnc

desktop_DATA = \
  desktop/org.opensuse.yast.SambaClient.desktop

scalabledir = @icondir@/hicolor/scalable/apps
scalable_DATA = \
  icons/hicolor/scalable/apps/yast-samba-client.svg

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(scrconf_DATA) $(agent_SCRIPTS) $(schemafiles_DATA) $(desktop_DATA) $(scalable_DATA)

include $(top_srcdir)/Makefile.am.common
