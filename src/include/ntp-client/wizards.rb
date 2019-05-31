# encoding: utf-8

# File:	include/ntp-client/wizards.ycp
# Package:	Configuration of ntp-client
# Summary:	Wizards definitions
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$

require "y2ntp_client/dialog/main"

module Yast
  module NtpClientWizardsInclude
    def initialize_ntp_client_wizards(include_target)
      Yast.import "UI"

      textdomain "ntp-client"

      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Sequencer"

      Yast.include include_target, "ntp-client/dialogs.rb"
    end

    # Whole configuration of ntp-client
    # @return sequence result
    def NtpClientSequence
      aliases = {
        "read"  => [lambda { ReadDialog() }, true],
        "main"  => lambda { Y2NtpClient::Dialog::Main.run },
        "write" => [lambda { WriteDialog() }, true]
      }

      sequence = {
        "ws_start" => "read",
        "read"     => { abort: :abort, next: "main" },
        "main"     => { abort: :abort, next: "write" },
        "write"    => { abort: :abort, next: :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("org.openSUSE.YaST.NTPClient")
      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret
    end
  end
end
