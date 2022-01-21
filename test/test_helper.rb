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

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end

  src_location = File.expand_path("../src", __dir__)
  # track all ruby files under src
  SimpleCov.track_files("#{src_location}/**/*.rb")

  # additionally use the LCOV format for on-line code coverage reporting at CI
  if ENV["CI"] || ENV["COVERAGE_LCOV"]
    require "simplecov-lcov"

    SimpleCov::Formatter::LcovFormatter.config do |c|
      c.report_with_single_file = true
      # this is the default Coveralls GitHub Action location
      # https://github.com/marketplace/actions/coveralls-github-action
      c.single_report_path = "coverage/lcov.info"
    end

    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ]
  end
end

# stub classes from other modules to avoid build dependencies
Yast::RSpec::Helpers.define_yast_module("Lan", methods: [:dhcp_ntp_servers])
Yast::RSpec::Helpers.define_yast_module("Language")
Yast::RSpec::Helpers.define_yast_module("PackageCallbacks")
Yast::RSpec::Helpers.define_yast_module("Pkg")
