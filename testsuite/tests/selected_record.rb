# encoding: utf-8

#
module Yast
  class SelectedRecordClient < Client
    def main
      Yast.include self, "testsuite.rb"
      # [COBE] why is all this necessary just to test a standalone function!
      # testedfiles: NtpClient.ycp
      @READ = { "target" => { "tmpdir" => "/tmp", "size" => 0 } }
      @EXECUTE = { "target" => { "bash_output" => {} } }
      TESTSUITE_INIT([@READ, {}, @EXECUTE], nil)

      Yast.import "NtpClient"

      NtpClient.selected_record = {
        "type"    => "server",
        "server"  => "tick.example.com",
        "options" => "whatever"
      }
      DUMP(NtpClient.selected_record)

      NtpClient.enableOptionInSyncRecord("iburst")
      DUMP(NtpClient.selected_record)

      NtpClient.enableOptionInSyncRecord("burst")
      DUMP(NtpClient.selected_record)

      NtpClient.selected_record = {}
      NtpClient.enableOptionInSyncRecord("alone")
      DUMP(NtpClient.selected_record)

      nil
    end
  end
end

Yast::SelectedRecordClient.new.main
