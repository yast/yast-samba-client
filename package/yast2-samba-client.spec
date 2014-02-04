#
# spec file for package yast2-samba-client
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-samba-client
Version:        3.1.3
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:          System/YaST
License:        GPL-2.0
BuildRequires:	yast2-pam yast2-perl-bindings perl-XML-Writer yast2-testsuite update-desktop-files
BuildRequires:  yast2-devtools >= 3.1.10
Requires:	perl-XML-LibXML
Conflicts:	yast2-kerberos-client < 3.1.2

# new Pam.ycp API
Requires:       yast2-pam >= 2.14.0

# .etc.ssh.sshd_config
# Wizard::SetDesktopTitleAndIcon
Requires:       yast2 >= 2.21.22

BuildArchitectures:	noarch

Requires:       yast2-ruby-bindings >= 1.0.0

Summary:	YaST2 - Samba Client Configuration

%description
This package contains the YaST2 component for configuration of an SMB
workgroup/domain and authentication against an SMB domain.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install


%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/samba-client
%{yast_yncludedir}/samba-client/*
%{yast_clientdir}/samba-client.rb
%{yast_clientdir}/samba-client_*.rb
%{yast_moduledir}/Samba*.pm
%{yast_moduledir}/Samba.rb
%{yast_desktopdir}/samba-client.desktop
%{yast_scrconfdir}/*.scr
%{yast_agentdir}/ag_pam_mount
%{yast_schemadir}/autoyast/rnc/samba-client.rnc
%doc %{yast_docdir}
