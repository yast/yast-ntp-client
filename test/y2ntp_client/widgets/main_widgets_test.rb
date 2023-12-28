require_relative "../../test_helper"

require "cwm/rspec"
require "y2ntp_client/widgets/main_widgets"

describe Y2NtpClient::Widgets::PolicyCombo do
  include_examples "CWM::ComboBox"
end

describe Y2NtpClient::Widgets::NtpStart do
  subject { described_class.new(double(replace: nil)) }

  include_examples "CWM::RadioButtons"
end

describe Y2NtpClient::Widgets::SyncInterval do
  include_examples "CWM::AbstractWidget"
end

describe Y2NtpClient::Widgets::ServersTable do
  before do
    allow(Yast::NtpClient).to receive(:ntp_conf)
      .and_return(double(
        pools:       { "ntp.org" => {}, "us.ntp.org" => {} },
        modify_pool: nil
      ))
    allow(subject).to receive(:value).and_return("ntp.org")
    allow(subject).to receive(:value=)
    allow(Y2NtpClient::Dialog::Pool).to receive(:new)
      .and_return(double(run: :next, resulting_pool: ["de.ntp.org", {}]))
  end

  include_examples "CWM::Table"
end

describe Y2NtpClient::Widgets::AddPoolButton do
  before do
    allow(Yast::NtpClient).to receive(:ntp_conf)
      .and_return(double(
        default_pool_options: {},
        add_pool:             nil
      ))
    allow(Y2NtpClient::Dialog::Pool).to receive(:new)
      .and_return(double(run: :next, resulting_pool: ["de.ntp.org", {}]))
  end

  include_examples "CWM::PushButton"
end

describe Y2NtpClient::Widgets::EditPoolButton do
  subject { described_class.new(double(value: "ntp.org", handle: nil)) }

  before do
    allow(Y2NtpClient::Dialog::Pool).to receive(:new)
      .and_return(double(run: :next, resulting_pool: ["de.ntp.org", {}]))
  end

  include_examples "CWM::PushButton"
end

describe Y2NtpClient::Widgets::DeletePoolButton do
  subject { described_class.new(double(value: "ntp.org")) }

  before do
    allow(Yast::Confirm).to receive(:Delete).and_return(true)
    allow(Yast::NtpClient).to receive(:ntp_conf).and_return(double(delete_pool: nil))
  end

  include_examples "CWM::PushButton"
end
