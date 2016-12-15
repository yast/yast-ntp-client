FROM opensuse:tumbleweed
RUN zypper ar -f http://download.opensuse.org/repositories/YaST:/Head/openSUSE_Tumbleweed/ yast
RUN zypper --gpg-auto-import-keys --non-interactive in \
      fdupes \
      grep \
      yast2-devtools \
      perl-XML-Writer \
      yast2 \
      yast2-country-data \
      yast2-devtools \
      'rubygem(rspec)' \
      'rubygem(yast-rake)' \
      augeas-lenses \
      'rubygem(cfa)' \
      'rubygem(gettext)' \
      'rubygem(simplecov)' \
      update-desktop-files \
      git \
      rpm-build \
      which
# FIXME: fix the dependency issues in YaST:Head and install them via zypper
# FIXME: switch to Rubocop 0.41.2 as the rest of YaST
RUN gem install --no-document coveralls yard rubocop:0.29.1
COPY . /tmp/sources
WORKDIR /tmp/sources

