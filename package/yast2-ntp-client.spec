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
Version:        3.2.11
Release:        0
Summary:        YaST2 - NTP Client Configuration
License:        GPL-2.0+
Group:          System/YaST
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2
BuildRequires:  perl-XML-Writer
BuildRequires:  update-desktop-files
BuildRequires:  yast2 >= 3.2.21
BuildRequires:  yast2-country-data
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  autoyast2-installation
BuildRequires:  rubygem(%rb_default_ruby_abi:rspec)
BuildRequires:  rubygem(%rb_default_ruby_abi:yast-rake)
BuildRequires:  augeas-lenses
BuildRequires:  rubygem(%rb_default_ruby_abi:cfa) >= 0.6.0

# proper acting TargetFile when scr is switched
Requires:       yast2 >= 3.2.21
Requires:       yast2-country-data
Requires:       yast2-ruby-bindings >= 1.0.0
Requires:       rubygem(%rb_default_ruby_abi:cfa) >= 0.6.0
Requires:       augeas-lenses
BuildArch:      noarch
# New sntp command line syntax
Conflicts:      ntp < 4.2.8

Obsoletes:      yast2-ntp-client-devel-doc

%description
This package contains the YaST2 component for NTP client configuration.

%prep
%setup -n %{name}-%{version}

%check
rake test:unit

%build

%install
rake install DESTDIR="%{buildroot}"

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/ntp-client
%{yast_clientdir}/*
%{yast_dir}/lib
%{yast_yncludedir}/ntp-client/*
%{yast_scrconfdir}/cfg_ntp.scr
%{yast_scrconfdir}/etc_ntp.scr
%{yast_moduledir}/*.rb
%{yast_desktopdir}/ntp-client.desktop
%{yast_ydatadir}/ntp_servers.yml
%{yast_schemadir}/autoyast/rnc/ntpclient.rnc
%{yast_dir}/lib

%dir %{yast_docdir}
%doc %{yast_docdir}/COPYING
%doc %{yast_docdir}/README.md
%doc %{yast_docdir}/CONTRIBUTING.md

%changelog
