# encoding: utf-8

# File:
#  Read.ycp
#
# Module:
#  NTP client configurator
#
# Summary:
#  Reading configuration testsuite
#
# Authors:
#  Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
module Yast
  class WriteClient < Client
    def main
      # testedfiles: NtpClient.ycp

      Yast.include self, "testsuite.rb"

      @READ = {
        "init"      => { "scripts" => { "exists" => true } },
        "etc"       => {
          "ntp_conf" => {
            "all" => {
              "comment" => "",
              "file"    => -1,
              "kind"    => "section",
              "name"    => "",
              "type"    => -1,
              "value"   => []
            }
          }
        },
        "sysconfig" => {
          "ntp"               => { "NTPD_RUN_CHROOTED" => "yes" },
          "personal-firewall" => { "REJECT_ALL_INCOMING_CONNECTIONS" => "no" }
        },
        "target"    => { "string" => "", "tmpdir" => "/tmp", "size" => 0 }
      }
      @WRITE = {}
      @EXEC = {
        "target" => {
          "bash_output" => {
            "exit" => 0,
            "stdout" => "",
            "stderr" => ""
          }
        }
      }


      TESTSUITE_INIT([@READ, @WRITE, @EXEC], nil)

      Yast.import "Progress"
      Yast.import "NtpClient"
      Yast.import "Mode"

      Mode.SetTest("testsuite")

      @progress_orig = Progress.set(false)

      TEST(lambda do
        NtpClient.Import(
          {
            "peers"           => [
              {
                "address"      => "ntp1",
                "initial_sync" => true,
                "options"      => " options1",
                "type"         => "server"
              },
              {
                "address"      => "127.127.1.2",
                "initial_sync" => false,
                "options"      => " options_clock",
                "type"         => "__clock"
              },
              {
                "address"      => "ntp2",
                "initial_sync" => true,
                "options"      => " options2",
                "type"         => "server"
              },
              {
                "address"      => "peer1",
                "initial_sync" => false,
                "options"      => " options_peer",
                "type"         => "peer"
              }
            ],
            "start_at_boot"   => false,
            "start_in_chroot" => true,
            "configure_dhcp"  => false
          }
        )
      end, [
        @READ,
        @WRITE,
        @EXEC
      ], nil)


      TEST(lambda { NtpClient.Write }, [@READ, @WRITE, @EXEC], nil)

      nil
    end
  end
end

Yast::WriteClient.new.main
