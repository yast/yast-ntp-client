require_relative "../../test_helper"

require "cwm/rspec"
require "y2ntp_client/dialog/main"

describe Y2NtpClient::Dialog::Main do
  include_examples "CWM::Dialog"
end
