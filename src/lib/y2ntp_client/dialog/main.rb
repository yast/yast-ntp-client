require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets"

Yast.import "Label"
Yast.import "Stage"

module Y2NtpClient
  module Dialog
    class Main < CWM::Dialog
      def initialize
        textdomain "ntp-client"
      end

      def title
        # dialog caption
        _("NTP Configuration")
      end

      def contents
        replace_point = CWM::ReplacePoint.new(widget: CWM::Empty.new("empty_interval"))
        VBox(
          HBox(
            Y2NtpClient::NtpStart.new(replace_point),
            HSpacing(1),
            replace_point
          ),
          VSpacing(1),
          Left(Y2NtpClient::PolicyCombo.new),
          VSpacing(1),
          Y2NtpClient::ServersTable.new
        )
      end

      def abort_button
        Yast::Label.CancelButton
      end

      def back_button
        # no back button
        ""
      end

      def next_button
        # FIXME: it probably cannot run in initial stage, so not needed
        Yast::Stage.initial ? Yast::Label.AcceptButton : Yast::Label.OKButton
      end
    end
  end
end
