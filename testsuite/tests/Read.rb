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
  class ReadClient < Client
    def main
      # testedfiles: NtpClient.ycp

      Yast.include self, "testsuite.rb"

      @READ = {
        "init"      => {
          "scripts" => { "exists" => true, "runlevel" => { "ntp" => {} } }
        },
        "etc"       => {
          "ntp_conf" => {
            "all" => {
              "comment" => "",
              "file"    => -1,
              "kind"    => "section",
              "name"    => "",
              "type"    => -1,
              "value"   => [
                {
                  "comment" => "",
                  "kind"    => "value",
                  "name"    => "server",
                  "type"    => 0,
                  "value"   => "ntp1 options1"
                },
                {
                  "comment" => "",
                  "kind"    => "value",
                  "name"    => "server",
                  "type"    => 0,
                  "value"   => "127.127.1.2 options_clock"
                },
                {
                  "comment" => "",
                  "kind"    => "value",
                  "name"    => "fudge",
                  "type"    => 0,
                  "value"   => "127.127.1.2fudge_clock"
                },
                {
                  "comment" => "",
                  "kind"    => "value",
                  "name"    => "server",
                  "type"    => 0,
                  "value"   => "ntp2 options2"
                },
                {
                  "comment" => "",
                  "kind"    => "value",
                  "name"    => "peer",
                  "type"    => 0,
                  "value"   => "peer1 options_peer"
                }
              ]
            }
          }
        },
        "sysconfig" => {
          "ntp"               => { "NTPD_RUN_CHROOTED" => "yes" },
          "personal-firewall" => { "REJECT_ALL_INCOMING_CONNECTIONS" => "no" },
          "network"           => {
            "config" => { "NETCONFIG_NTP_POLICY" => "" },
            "dhcp"   => { "DHCLIENT_MODIFY_NTP_CONF" => "no" }
          }
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
        },
        "bash" => 1
      }

      TESTSUITE_INIT([@READ, @WRITE, @EXEC], nil)

      Yast.import "Progress"
      Yast.import "NtpClient"
      Yast.import "Mode"

      Mode.SetTest("testsuite")

      @progress_orig = Progress.set(false)

      TEST(lambda { NtpClient.Read }, [@READ, @WRITE, @EXEC], nil)
      TEST(lambda { NtpClient.Export }, [@READ, @WRITE, @EXEC], nil)

      nil
    end
  end
end

Yast::ReadClient.new.main
