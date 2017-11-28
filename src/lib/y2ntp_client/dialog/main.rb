require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets/main_widgets"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Stage"

module Y2NtpClient
  module Dialog
    # Main entry point for Ntp Client
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
        table = Widgets::ServersTable.new
        VBox(
          HBox(
            HWeight(1, Widgets::NtpStart.new(replace_point)),
            HSpacing(1),
            HWeight(1, replace_point)
          ),
          VSpacing(1),
          Left(Widgets::PolicyCombo.new),
          VSpacing(1),
          *hardware_clock_widgets,
          HBox(
            table,
            HSpacing(0.2),
            VBox(
              VSpacing(),
              Widgets::AddPoolButton.new,
              VSpacing(),
              Widgets::EditPoolButton.new(table),
              VSpacing(),
              Widgets::DeletePoolButton.new(table),
              VStretch()
            )
          )
        )
      end

      def run
        loop do
          res = super
          return res if res != :redraw
        end
      end

      def abort_button
        Yast::Label.CancelButton
      end

      def hardware_clock_widgets
        if Yast::NtpClient.ntp_conf.hardware_clock?
          [
            Label(_("Hardware clock configured as source. YaST will keep it untouched.")),
            VSpacing(1)
          ]
        else
          [Empty()]
        end
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
