# encoding: utf-8

# File:	clients/ntp-client.ycp
# Package:	Configuration of ntp-client
# Summary:	Main file
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Main file for ntp-client configuration. Uses all other files.

Yast.import "Stage"

module Yast
  class NtpClientClient < Client
    def main
      Yast.import "UI"

      # **
      # <h3>Configuration of the ntp-client</h3>

      textdomain "ntp-client"

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("NtpClient module started")

      Yast.import "CommandLine"
      Yast.import "NtpClient"

      Yast.include self, "ntp-client/wizards.rb"

      Yast.include self, "ntp-client/commandline.rb"

      # main ui function
      @ret = CommandLine.Run(@cmdline)
      Builtins.y2debug("ret=%1", @ret)

      # Finish
      Builtins.y2milestone("NtpClient module finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret)

      # EOF
    end

    # CommandLine handler for running GUI
    # @return [Boolean,Symbol] true if settings were saved; :next, :abort or :back
    #   when running in 'firstboot'
    def GuiHandler
      ret = NtpClientSequence()
      return ret if Yast::Stage.firstboot
      return false if ret == :abort || ret == :back || ret.nil?
      true
    end
  end
end

Yast::NtpClientClient.new.main
