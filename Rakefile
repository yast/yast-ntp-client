require "yast/rake"

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/
  conf.install_locations["src/systemd/*"] =
    Packaging::Configuration::DESTDIR + "/usr/lib/systemd/system/"
end
