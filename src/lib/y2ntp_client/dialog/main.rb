require "yast"

require "cwm/dialog"
require "y2ntp_client/widgets/main_widgets"

Yast.import "Label"
Yast.import "NtpClient"
Yast.import "Mode"

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
          table,
          HSpacing(0.2),
          Left(
            HBox(
              Widgets::AddPoolButton.new,
              HSpacing(),
              Widgets::EditPoolButton.new(table),
              HSpacing(),
              Widgets::DeletePoolButton.new(table)
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
        return Yast::Label.CancelButton unless installation?

        nil
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
        return "" unless installation?

        nil
      end

      def next_button
        return Yast::Label.OKButton unless installation?

        nil
      end

      # Determines whether running in installation mode
      #
      # We do not use Stage.initial because of firstboot, which runs in 'installation' mode
      # but in 'firstboot' stage.
      #
      # @return [Boolean] Boolean if running in installation or update mode
      def installation?
        Yast::Mode.installation || Yast::Mode.update
      end
    end
  end
end
