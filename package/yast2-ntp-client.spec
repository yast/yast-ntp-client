#
# spec file for package yast2-ntp-client
#
# Copyright (c) 2014 SUSE LINUX Products GmbH, Nuernberg, Germany.
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


Name:           yast2-ntp-client
Version:        3.1.12.4
Release:        0
Summary:        YaST2 - NTP Client Configuration
License:        GPL-2.0+
Group:          System/YaST
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2
BuildRequires:  perl-XML-Writer
BuildRequires:  update-desktop-files
BuildRequires:  yast2 >= 3.1.11
BuildRequires:  yast2-country-data
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  yast2-testsuite
#SLPAPI.pm 
# Hostname::CurrentDomain
# Wizard::SetDesktopTitleAndIcon
Requires:       yast2 >= 3.1.11
Requires:       yast2-country-data
Requires:       yast2-ruby-bindings >= 1.0.0
BuildArch:      noarch
# New sntp command line syntax
Conflicts:      ntp < 4.2.8


%description
This package contains the YaST2 component for NTP client configuration.

%package devel-doc
Requires:       yast2-ntp-client = %version
Summary:        YaST2 - NTP Client - Development Documentation
Group:          System/YaST

%description devel-doc
This package contains development documentation for using the API
provided by yast2-ntp-client package.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/ntp-client
%{yast_yncludedir}/ntp-client/*
%{yast_clientdir}/ntp-client.rb
%{yast_clientdir}/ntp-client_*.rb
%{yast_scrconfdir}/cfg_ntp.scr
%{yast_scrconfdir}/etc_ntp.scr
%{yast_moduledir}/*.rb
%{yast_desktopdir}/ntp-client.desktop
%{yast_ydatadir}/ntp_servers.yml
%{yast_schemadir}/autoyast/rnc/ntpclient.rnc

%dir %{yast_docdir}
%doc %{yast_docdir}/COPYING
%doc %{yast_docdir}/TODO
%doc %{yast_docdir}/spec.txt

%files devel-doc
%doc %{yast_docdir}/autodocs
%doc %{yast_docdir}/ntp.conf_agent.txt

%changelog
