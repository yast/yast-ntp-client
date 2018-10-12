require_relative "../../test_helper"

require "cwm/rspec"
require "y2ntp_client/dialog/pool"

describe Y2NtpClient::Dialog::Pool do
  include_examples "CWM::Dialog"
end
