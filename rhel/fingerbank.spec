Name:       fingerbank
Version:    1.0.4
Release:    1%{?dist}
BuildArch:  noarch
Summary:    An exhaustive profiling tool
Packager:   Inverse inc. <info@inverse.ca>
Group:      System Environment/Daemons
License:    GPL
URL:        http://www.fingerbank.org/

Source0:    https://support.inverse.ca/~dwuelfrath/fingerbank.tar.gz

BuildRoot:  %{_tmppath}/%{name}-root

Requires(post):     /sbin/chkconfig
Requires(preun):    /sbin/chkconfig

Requires(pre):      /usr/sbin/useradd, /usr/sbin/groupadd, /usr/bin/getent
Requires(postun):   /usr/sbin/userdel

Requires:   perl
Requires:   perl-version
Requires:   perl(Catalyst::Runtime)
Requires:   perl(aliased)
Requires:   perl(MooseX::Types::LoadableClass)
Requires:   perl(Catalyst::Plugin::Static::Simple)
Requires:   perl(Catalyst::Plugin::ConfigLoader)
Requires:   perl(Config::General)
Requires:   perl(Readonly)
Requires:   perl(Log::Log4perl)
Requires:   perl(Catalyst::Model::DBIC::Schema)
Requires:   perl(Catalyst::Action::REST)
Requires:   perl(DBD::SQLite)
Requires:   perl(JSON::MaybeXS)
Requires:   perl(LWP::Protocol::https)
Requires:   perl(MooseX::NonMoose)

%description
Fingerbank


%pre
/usr/bin/getent group fingerbank || /usr/sbin/groupadd -r fingerbank
/usr/bin/getent passwd fingerbank || /usr/sbin/useradd -r -d /usr/local/fingerbank -s /sbin/nologin -g fingerbank fingerbank


%prep
%setup -q


%build


%install
# /usr/local/fingerbank
rm -rf %{buildroot}
%{__install} -d $RPM_BUILD_ROOT/usr/local/fingerbank
cp -r * $RPM_BUILD_ROOT/usr/local/fingerbank
touch $RPM_BUILD_ROOT/usr/local/fingerbank/logs/fingerbank.log

# Logrotate
%{__install} -d $RPM_BUILD_ROOT/etc/logrotate.d
cp rhel/fingerbank.logrotate $RPM_BUILD_ROOT/etc/logrotate.d/fingerbank


%post
# Local database initialization
/usr/local/fingerbank/db/init_databases.pl
chown fingerbank.fingerbank /usr/local/fingerbank/db/fingerbank_Local.db
chmod 664 /usr/local/fingerbank/db/fingerbank_Local.db

# Log file handling
if [ ! -e /usr/local/fingerbank/logs/fingerbank.log ]; then
    touch /usr/local/fingerbank/logs/fingerbank.log
    chown fingerbank.fingerbank /usr/local/fingerbank/logs/fingerbank.log
fi


%clean
rm -rf %{buildroot}


%postun


%files
%defattr(664,fingerbank,fingerbank,2775)
%dir                                /usr/local/fingerbank
                                    /usr/local/fingerbank/*
%attr(775,fingerbank,fingerbank)    /usr/local/fingerbank/db/init_databases.pl
%dir                                %{_sysconfdir}/logrotate.d
%config                             %{_sysconfdir}/logrotate.d/fingerbank
%ghost                              /usr/local/fingerbank/logs/fingerbank.log
%attr(664,fingerbank,fingerbank)    /usr/local/fingerbank/logs/fingerbank.log


%changelog
