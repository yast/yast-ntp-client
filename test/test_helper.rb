ENV["Y2DIR"] = File.expand_path("../src", __dir__)
ENV["LC_ALL"] = "en_US.utf8"

require "yast"
require "yast/rspec"
require "yaml"
require "pathname"

TESTS_PATH = Pathname.new(File.dirname(__FILE__))
DATA_PATH = TESTS_PATH.join("data")

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    # If you misremember a method name both in code and in tests,
    # will save you.
    # https://relishapp.com/rspec/rspec-mocks/v/3-0/docs/verifying-doubles/partial-doubles
    #
    # With graceful degradation for RSpec 2
    mocks.verify_partial_doubles = true if mocks.respond_to?(:verify_partial_doubles=)
  end
end

# stub module to prevent its Import
# Useful for modules from different yast packages, to avoid build dependencies
def stub_module(name, fake_class = nil)
  fake_class = Class.new { def self.fake_method; end } if fake_class.nil?
  Yast.const_set name.to_sym, fake_class
end

# stub classes from other modules to speed up a build
stub_module("Lan", Class.new { def dhcp_ntp_servers; []; end })
stub_module("Language")
stub_module("Pkg")
stub_module("PackageCallbacks")

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end

  src_location = File.expand_path("../src", __dir__)
  # track all ruby files under src
  SimpleCov.track_files("#{src_location}/**/*.rb")

  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    ]
  end
end
