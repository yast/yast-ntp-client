#
# spec file for package yast2-ntp-client
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
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
Version:        4.1.12
Release:        0
Summary:        YaST2 - NTP Client Configuration
License:        GPL-2.0-or-later
Group:          System/YaST
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2
BuildRequires:  augeas-lenses
BuildRequires:  autoyast2-installation
BuildRequires:  perl-XML-Writer
BuildRequires:  update-desktop-files
# cwm/popup
BuildRequires:  yast2 >= 4.1.15
BuildRequires:  yast2-country-data
BuildRequires:  yast2-devtools >= 3.1.10
BuildRequires:  rubygem(%rb_default_ruby_abi:cfa) >= 0.6.0
BuildRequires:  rubygem(%rb_default_ruby_abi:rspec)
BuildRequires:  rubygem(%rb_default_ruby_abi:yast-rake)

# proper acting TargetFile when scr is switched
Requires:       augeas-lenses
# cwm/popup
Requires:       yast2 >= 4.1.15
Requires:       yast2-country-data
# needed for network/config agent
# Yast::Lan.dhcp_ntp_servers
Requires:       yast2-network >= 4.1.17
Requires:       yast2-ruby-bindings >= 1.0.0
Requires:       rubygem(%rb_default_ruby_abi:cfa) >= 0.6.0
BuildArch:      noarch

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

%post
# upgrade old name and convert it to chrony (bsc#1079122)
if [ -f /etc/cron.d/novell.ntp-synchronize ]; then
  mv /etc/cron.d/novell.ntp-synchronize /etc/cron.d/suse-ntp_synchronize
  sed -i 's:\* \* \* \* root .*:* * * * root /usr/sbin/chronyd -q \&>/dev/null:' /etc/cron.d/suse-ntp_synchronize
fi

%files
%defattr(-,root,root)
%dir %{yast_yncludedir}/ntp-client
%{yast_clientdir}/*
%{yast_dir}/lib
%{yast_yncludedir}/ntp-client/*
%{yast_moduledir}/*.rb
%{yast_desktopdir}/ntp-client.desktop
%{yast_ydatadir}/ntp_servers.yml
%{yast_schemadir}/autoyast/rnc/ntpclient.rnc
%{yast_dir}/lib
%ghost /etc/cron.d/suse-ntp_synchronize
%{yast_icondir}
%dir %{yast_docdir}
%license COPYING
%doc %{yast_docdir}/README.md
%doc %{yast_docdir}/CONTRIBUTING.md

%changelog
