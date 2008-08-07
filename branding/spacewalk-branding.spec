Name:       spacewalk-branding
Version:    0.1.3
Release:    0%{?dist}
Summary:    Spacewalk branding data

Group:      Applications/Internet
License:    GPLv2
URL:        https://fedorahosted.org/spacewalk/
Source0:    %{name}-%{version}.tar.gz
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:  noarch

Requires:   spacewalk-html


%description
Spacewalk specific branding, CSS, and images.


%prep
%setup -q


%build


%install
rm -rf %{buildroot}
install -d -m 755 %{buildroot}/%{_var}/www/html
cp -R css %{buildroot}/%{_var}/www/html/
cp -R img %{buildroot}/%{_var}/www/html/
cp -R templates %{buildroot}/%{_var}/www/html/


%clean
rm -rf %{buildroot}


%files
%defattr(-,root,root,-)
%dir /%{_var}/www/html/css
/%{_var}/www/html/css/*
%dir /%{_var}/www/html/img
/%{_var}/www/html/img/*
%dir /%{_var}/www/html/templates
/%{_var}/www/html/templates/*
/%{_var}/www/html/templates/.htaccess


%changelog
* Thu Aug  7 2008 Devan Goodwin 0.1.3-0
- Adding templates.

* Wed Aug  6 2008 Jan Pazdziora 0.1.2-0
- decrease version to 0.1.*
- tag for rebuild

* Mon Aug 04 2008  Miroslav Suchy <msuchy@redhat.com>
- fix dependecies, requires spacewalk-html
- bump version

* Wed Jul 30 2008  Devan Goodwin <dgoodwin@redhat.com> 0.2-2
- Adding images.

* Tue Jul 29 2008  Devan Goodwin <dgoodwin@redhat.com> 0.2-1
- Initial packaging.

