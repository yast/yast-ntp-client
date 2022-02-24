#! /usr/bin/env rspec
require_relative "../../test_helper"

require "cwm/rspec"
require "y2ntp_client/widgets/pool_widgets"

describe Y2NtpClient::Widgets::PoolAddress do
  subject { described_class.new("test.ntp.org") }

  include_examples "CWM::AbstractWidget"
end

describe Y2NtpClient::Widgets::TestButton do
  subject { described_class.new(double(value: "test.ntp.org")) }

  before do
    # allow test fail in test env
    allow(Yast::Report).to receive(:Error)
  end

  include_examples "CWM::PushButton"
end

describe Y2NtpClient::Widgets::Iburst do
  subject { described_class.new({}) }

  include_examples "CWM::CheckBox"
end

describe Y2NtpClient::Widgets::Offline do
  subject { described_class.new({}) }

  include_examples "CWM::CheckBox"
end

describe Y2NtpClient::Widgets::LocalList do
  subject { described_class.new({}) }

  include_examples "CWM::ComboBox"
end

describe Y2NtpClient::Widgets::PublicList do
  subject { described_class.new({}) }

  include_examples "CWM::CustomWidget"
end

describe Y2NtpClient::Widgets::SelectFrom do
  subject { described_class.new({}) }

  include_examples "CWM::AbstractWidget"
end
