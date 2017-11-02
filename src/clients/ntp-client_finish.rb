# encoding: utf-8

# File:	clients/ntp-client_finish.ycp
# Summary:	Installation client for writing ntp configuration
#		at the end of 1st stage
# Author:	Bubli <kmachalkova@suse.cz>
#
module Yast
  class NtpClientFinishClient < Client
    def main
      textdomain "ntp-client"

      Yast.import "NtpClient"

      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end

      Builtins.y2milestone("starting ntp-client_finish")
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      if @func == "Info"
        return {
          "steps" => 1,
          # progress step title
          "title" => _("Writing NTP Configuration..."),
          "when"  => NtpClient.modified ? [:installation, :autoinst] : []
        }
      elsif @func == "Write"
        # bnc#449615, must merge the configs which Export/Import fails to do.

        # User config from installation time:
        # fortunately so far we only have the server address(es)
        pools = NtpClient.ntp_conf.pools

        # ntp.conf from the RPM
        NtpClient.config_has_been_read = false
        NtpClient.ProcessNtpConf

        # put users server(s) back
        NtpClient.ntp_conf.clear_pools

        pools.each_pair do |server, options|
          NtpClient.ntp_conf.add_pool(server, options)
        end

        NtpClient.write_only = true

        NtpClient.Write
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = nil
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("ntp-client_finish finished")
      deep_copy(@ret)
    end
  end
end

Yast::NtpClientFinishClient.new.main
