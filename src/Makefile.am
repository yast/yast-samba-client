#
# Makefile.am for devtools/devtools/skeletons/config/src
#

yncludedir = @yncludedir@/samba-client

client_DATA =			\
	samba-client.ycp		\
	samba-client_auto.ycp	

ynclude_DATA =			\
	helps.ycp		\
	wizards.ycp		\
	dialogs.ycp		\
	complex.ycp		\
	routines.ycp

config_DATA =			\
	samba-client.y2cc

desktop_DATA =			\
	samba-client.desktop

module_DATA =			\
	Samba.ycp

E XTRA_DIST = $(client_DATA) $(ynclude_DATA) $(config_DATA) $(module_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common

