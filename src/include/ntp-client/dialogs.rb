# encoding: utf-8

# File:	clients/ntp-client.ycp
# Package:	Configuration of ntp-client
# Summary:	Main file
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
# Main file for ntp-client configuration. Uses all other files.
module Yast
  module NtpClientDialogsInclude
    def initialize_ntp_client_dialogs(include_target)
      textdomain "ntp-client"

      Yast.import "CWM"
      Yast.import "CWMTab"
      Yast.import "Label"
      Yast.import "NtpClient"
      Yast.import "Popup"
      Yast.import "Stage"
      Yast.import "SuSEFirewall"
      Yast.import "Wizard"
      Yast.import "Report"
      Yast.import "Confirm"

      Yast.include include_target, "ntp-client/misc.rb"
      Yast.include include_target, "ntp-client/widgets.rb"

      @widgets = nil
    end

    # Get the map of all widgets
    # @return a map with all widgets for CWM
    def GetWidgets
      @widgets = InitWidgets() if @widgets.nil?
      deep_copy(@widgets)
    end

    # Display the popup to confirm abort
    # @return [Boolean] true if confirmed
    def abortPopup
      Popup.ReallyAbort(true)
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))

      # checking for root permissions (#158483)
      return :abort if !Stage.initial && !Confirm.MustBeRoot

      NtpClient.AbortFunction = fun_ref(method(:PollAbort), "boolean ()")
      ret = NtpClient.Read
      NtpClient.AbortFunction = nil
      ret ? :next : :abort
    end

    # Write settings dialog
    # @return `abort if aborted and `next otherwise
    def WriteDialog
      return :next if Stage.initial

      Wizard.RestoreHelp(Ops.get_string(@HELPS, "write", ""))
      NtpClient.AbortFunction = fun_ref(method(:PollAbort), "boolean ()")
      ret = NtpClient.Write
      NtpClient.AbortFunction = nil
      ret ? :next : :abort
    end

    # Main dialog
    # @return [Symbol] for wizard sequencer
    def SimpleDialog
      NtpClient.simple_dialog = true

      w = CWM.CreateWidgets(
        [
          "start",
          "interval",
          "server_address",
          "use_random_servers",
          "complex_button"
        ],
        GetWidgets()
      )
      contents = HBox(
        HSpacing(1),
        VBox(
          VStretch(),
          HBox(HStretch(), "start", HStretch()),
          VStretch(),
          "interval",
          VStretch(),
          HBox(
            HStretch(),
            Frame(
              # frame label
              _("NTP Server Configuration"),
              VBox(Left("use_random_servers"), "server_address")
            ),
            HStretch()
          ),
          VStretch(),
          "complex_button",
          VStretch()
        ),
        HSpacing(1)
      )

      # dialog caption
      caption = _("NTP Configuration")
      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        help,
        Label.BackButton,
        Stage.initial ? Label.AcceptButton : Label.OKButton
      )
      Wizard.HideBackButton
      Wizard.SetAbortButton(:abort, Label.CancelButton)

      startInit(nil)
      CWM.handleWidgets(w, "ID" => "never")

      ret = CWM.Run(
        w,
        # yes-no popup
        abort: fun_ref(method(:reallyExitSimple), "boolean ()")
      )

      Builtins.y2milestone("Simple dialog: Returning %1", ret)
      ret
    end

    # Main dialog
    # @return [Symbol] for wizard sequencer
    def MainDialog
      NtpClient.simple_dialog = false

      tab1 = HBox(
        HSpacing(1),
        VBox(
          VSpacing(1),
          HBox(
            VBox(
              "start",
              VSpacing(),
              HBox("policy_combo", "custom_policy"),
              VSpacing(),
              "interval",
              VSpacing()
            )
          ),
          VSpacing(1),
          "overview",
          VSpacing(1)
        ),
        HSpacing(1)
      )

      tab2 = HBox(
        HSpacing(1),
        VBox(
          VSpacing(1),
          HBox(
            VBox(
              "firewall"
            )
          ),
          VStretch()
        ),
        HSpacing(1)
      )

      tabs = {
        "general"  => {
          "header"       => _("General Settings"),
          "contents"     => tab1,
          "widget_names" => [
            "start",
            "policy_combo",
            "custom_policy",
            "interval",
            "overview"
          ]
        },
        "security" => {
          "header"       => _("Security Settings"),
          "contents"     => tab2,
          "widget_names" => ["firewall"]
        }
      }

      wd = {
        "tab" => CWMTab.CreateWidget(
          "tab_order"    => ["general", "security"],
          "tabs"         => tabs,
          "widget_descr" => GetWidgets(),
          "initial_tab"  => "general",
          "tab_help"     => ""
        )
      }

      contents = VBox("tab")
      w = CWM.CreateWidgets(
        ["tab"],
        Convert.convert(
          wd,
          from: "map <string, any>",
          to:   "map <string, map <string, any>>"
        )
      )

      # dialog caption
      caption = _("Advanced NTP Configuration")
      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        help,
        Label.BackButton,
        Stage.initial ? Label.AcceptButton : Label.OKButton
      )
      Wizard.HideBackButton
      Wizard.SetAbortButton(:abort, Label.CancelButton)

      # CWM::handleWidgets (w, $["ID" : "never"]);

      CWM.Run(
        w,
        abort: fun_ref(method(:reallyExitComplex), "boolean ()")
      )
    end

    # Type of new peer selection dialog
    # @return [Symbol] for wizard sequencer
    def TypeSelectDialog
      contents = HBox(
        HStretch(),
        VBox(VSpacing(3), "peer_types", VSpacing(3)),
        HStretch()
      )

      # dialog caption
      caption = _("New Synchronization")

      CWM.ShowAndRun(
        "widget_names"       => ["peer_types"],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.NextButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Server editing dialog
    # @return [Symbol] for wizard sequencer
    def ServerDialog
      contents = HBox(
        HStretch(),
        VBox(
          VSpacing(2),
          Frame(
            _("Server Settings"),
            VBox(
              "server_address",
              VSpacing(0.5),
              "options",
              VSpacing(0.5),
              "ac_options",
              VSpacing(0.5)
            )
          ),
          VSpacing(2)
        ),
        HStretch()
      )

      # dialog caption
      caption = _("NTP Server")

      CWM.ShowAndRun(
        "widget_names"       => ["server_address", "options", "ac_options"],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.OKButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Dialog for selecting local server from a list
    # @return [Symbol] for wizard sequencer
    def LocalServerSelectionDialog
      widgets = CWM.CreateWidgets(
        ["found_servers", "select_test_local"],
        GetWidgets()
      )

      contents = HBox(
        HSpacing(1),
        VBox(
          Frame(
            # TRANSLATORS: frame label
            _("Local NTP Server"),
            VBox(
              VSpacing(1),
              Ops.get_term(widgets, [0, "widget"], Empty()),
              VSpacing(1),
              Ops.get_term(widgets, [1, "widget"], Empty())
            )
          ),
          VSpacing(1),
          ButtonBox(
            PushButton(Id(:next), Label.OKButton),
            PushButton(Id(:back), Label.CancelButton)
          )
        ),
        HSpacing(1)
      )

      UI.OpenDialog(Opt(:decorated), contents)

      ret = CWM.Run(
        widgets,
        abort: fun_ref(method(:abortPopup), "boolean ()"),
        ok:    true,
        back:  false
      )

      UI.CloseDialog

      ret
    end

    # Dialog for selecting local server from a list
    # @return [Symbol] for wizard sequencer
    def PublicServerSelectionDialog
      widgets = CWM.CreateWidgets(
        ["servers_list", "select_test_public"],
        GetWidgets()
      )

      contents = HBox(
        HSpacing(1),
        VBox(
          Frame(
            # TRANSLATORS: frame label
            _("Public NTP Server"),
            VBox(
              VSpacing(1),
              Ops.get_term(widgets, [0, "widget"], Empty()),
              VSpacing(1),
              Ops.get_term(widgets, [1, "widget"], Empty())
            )
          ),
          VSpacing(1),
          ButtonBox(
            PushButton(Id(:next), Label.OKButton),
            PushButton(Id(:back), Label.CancelButton)
          )
        ),
        HSpacing(1)
      )

      UI.OpenDialog(Opt(:decorated), contents)

      ret = CWM.Run(
        widgets,
        abort: fun_ref(method(:abortPopup), "boolean ()"),
        ok:    true,
        back:  false
      )

      UI.CloseDialog

      ret
    end

    # Peer editing dialog
    # @return [Symbol] for wizard sequencer
    def PeerDialog
      contents = HBox(
        HStretch(),
        VBox(VSpacing(3), "paddress", VSpacing(1), "options", VSpacing(3)),
        HStretch()
      )

      # dialog caption
      caption = _("NTP Peer")

      CWM.ShowAndRun(
        "widget_names"       => ["paddress", "options"],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.OKButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Reference clock editing dialog
    # @return [Symbol] for wizard sequencer
    def RadioDialog
      contents = HBox(
        HSpacing(3),
        VBox(
          VSpacing(0.5),
          HBox("clock_type", HStretch()),
          HBox("unit_number", HStretch()),
          VSpacing(0.5),
          HBox("create_symlink", HStretch()),
          HBox("device", VBox(Label(""), "browse"), HStretch()),
          VSpacing(0.5),
          "options",
          VSpacing(0.5),
          "fudge_button",
          VSpacing(1)
        ),
        HSpacing(3)
      )

      # dialog caption
      caption = _("Local Reference Clock")

      CWM.ShowAndRun(
        "widget_names"       => [
          "clock_type",
          "unit_number",
          "create_symlink",
          "device",
          "browse",
          "options",
          "fudge_button"
        ],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.OKButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Broadcast editing dialog
    # @return [Symbol] for wizard sequencer
    def BCastDialog
      contents = HBox(
        HStretch(),
        VBox(VSpacing(3), "bcaddress", VSpacing(1), "options", VSpacing(3)),
        HStretch()
      )

      # dialog caption
      caption = _("Outgoing Broadcast")

      CWM.ShowAndRun(
        "widget_names"       => ["bcaddress", "options"],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.OKButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Broadcast client editing dialog
    # @return [Symbol] for wizard sequencer
    def BCastClientDialog
      contents = HBox(
        HStretch(),
        VBox(VStretch(), "bccaddress", VStretch()),
        HStretch()
      )

      # dialog caption
      caption = _("Incoming Broadcast")

      CWM.ShowAndRun(
        "widget_names"       => ["bccaddress"],
        "widget_descr"       => GetWidgets(),
        "contents"           => contents,
        "caption"            => caption,
        "back_button"        => Label.BackButton,
        "next_button"        => Label.OKButton,
        "fallback_functions" => {
          abort: fun_ref(method(:abortPopup), "boolean ()")
        }
      )
    end

    # Fudge factors dialog
    # @return [Symbol] for wizard sequencer
    def FudgeDialog
      contents = HBox(
        HSpacing(3),
        VBox(
          VSpacing(3),
          HBox(
            # text entry
            HWeight(1, TextEntry(Id(:refid), _("&Reference ID"), "")),
            HSpacing(3),
            # int field
            HWeight(1, IntField(Id(:stratum), _("&Stratum"), 0, 15, 2))
          ),
          VStretch(),
          HBox(
            # text entry
            HWeight(1, TextEntry(Id(:time1), _("Calibration Offset 1"))),
            HSpacing(3),
            # text entry
            HWeight(1, TextEntry(Id(:time2), _("Calibration Offset 2")))
          ),
          VStretch(),
          HBox(
            # check box
            HWeight(1, CheckBox(Id(:flag1), _("Flag &1"), false)),
            HSpacing(3),
            # check box
            HWeight(1, CheckBox(Id(:flag2), _("Flag &2"), false))
          ),
          VStretch(),
          HBox(
            # check box
            HWeight(1, CheckBox(Id(:flag3), _("Flag &3"), false)),
            HSpacing(3),
            # check box
            HWeight(1, CheckBox(Id(:flag4), _("Flag &4"), false))
          ),
          VSpacing(3)
        ),
        HSpacing(3)
      )

      # dialog caption
      caption = _("Clock Driver Calibration")

      Wizard.SetContentsButtons(
        caption,
        contents,
        fudgeHelp,
        Label.BackButton,
        Label.NextButton
      )

      options = string2opts(
        Ops.get_string(NtpClient.selected_record, "fudge_options", ""),
        [
          "time1",
          "time2",
          "stratum",
          "refid",
          "flag1",
          "flag2",
          "flag3",
          "flag4"
        ],
        []
      )
      Builtins.y2error("Options: %1", options)

      UI.ChangeWidget(
        Id(:refid),
        :Value,
        Ops.get_string(options, ["parsed", "refid"], "")
      )
      UI.ChangeWidget(
        Id(:stratum),
        :Value,
        Builtins.tointeger(Ops.get_string(options, ["parsed", "stratum"], "3"))
      )
      UI.ChangeWidget(
        Id(:time1),
        :Value,
        Ops.get_string(options, ["parsed", "time1"], "")
      )
      UI.ChangeWidget(
        Id(:time2),
        :Value,
        Ops.get_string(options, ["parsed", "time2"], "")
      )
      UI.ChangeWidget(
        Id(:flag1),
        :Value,
        Ops.get_string(options, ["parsed", "flag1"], "") == "1"
      )
      UI.ChangeWidget(
        Id(:flag2),
        :Value,
        Ops.get_string(options, ["parsed", "flag2"], "") == "1"
      )
      UI.ChangeWidget(
        Id(:flag3),
        :Value,
        Ops.get_string(options, ["parsed", "flag3"], "") == "1"
      )
      UI.ChangeWidget(
        Id(:flag4),
        :Value,
        Ops.get_string(options, ["parsed", "flag4"], "") == "1"
      )

      UI.ChangeWidget(Id(:time1), :ValidChars, "1234567890.")
      UI.ChangeWidget(Id(:time2), :ValidChars, "1234567890.")

      ret = nil
      ret = UI.UserInput while ret.nil?
      ret = :abort if ret == :cancel
      return Convert.to_symbol(ret) if ret == :back || ret == :abort
      if ret == :next
        Ops.set(
          options,
          ["parsed", "refid"],
          UI.QueryWidget(Id(:refid), :Value)
        )
        Ops.set(
          options,
          ["parsed", "stratum"],
          UI.QueryWidget(Id(:stratum), :Value)
        )
        Ops.set(
          options,
          ["parsed", "time1"],
          UI.QueryWidget(Id(:time1), :Value)
        )
        Ops.set(
          options,
          ["parsed", "time2"],
          UI.QueryWidget(Id(:time2), :Value)
        )
        Ops.set(
          options,
          ["parsed", "flag1"],
          Convert.to_boolean(UI.QueryWidget(Id(:flag1), :Value)) ? 1 : 0
        )
        Ops.set(
          options,
          ["parsed", "flag2"],
          Convert.to_boolean(UI.QueryWidget(Id(:flag2), :Value)) ? 1 : 0
        )
        Ops.set(
          options,
          ["parsed", "flag3"],
          Convert.to_boolean(UI.QueryWidget(Id(:flag3), :Value)) ? 1 : 0
        )
        Ops.set(
          options,
          ["parsed", "flag4"],
          Convert.to_boolean(UI.QueryWidget(Id(:flag4), :Value)) ? 1 : 0
        )
        Ops.set(
          NtpClient.selected_record,
          "fudge_options",
          opts2string(
            Ops.get_map(options, "parsed", {}),
            Ops.get_string(options, "unknown", "")
          )
        )
      end
      Convert.to_symbol(ret)
    end

    # fake dialogs (WS switches)

    # Pseudo-dialog to fetch information for the simple dialog
    # @return [Symbol] for wizard sequencer (always `next)
    def SimpleDialogPrepare
      peers = NtpClient.getSyncRecords
      servers = Builtins.filter(peers) do |m|
        Ops.get_string(m, "type", "") == "server"
      end
      index = Ops.get_integer(servers, [0, "index"], -1)
      NtpClient.selectSyncRecord(index)
      :next
    end

    # Pseudo-dialog to store information after the simple dialog
    # @return [Symbol] for wizard sequencer (always `next)
    def SimpleDialogFinish
      if Ops.get_string(NtpClient.selected_record, "address", "") != ""
        NtpClient.storeSyncRecord
      end
      :next
    end

    # Pseudo-dialog to store settings to main structure
    # @return [Symbol] for wizard sequencer

    def StoreRecord
      @sync_record_modified = true
      NtpClient.storeSyncRecord
      :next
    end

    # Select the type of configuration - simple vs. complex
    # @return [Symbol] for ws `simple or `complex
    def SelectConfigType
      if NtpClient.PolicyIsNonstatic
        Builtins.y2milestone("Netconfig nonstatic configuration")
        return :complex
      end
      peers = NtpClient.getSyncRecords
      servers = Builtins.filter(peers) do |m|
        Ops.get_string(m, "type", "") == "server"
      end
      clocks = Builtins.filter(peers) do |m|
        Ops.get_string(m, "type", "") == "__clock"
      end

      random_pool_servers_enabled_only =
        # number of listed servers is the same as the needed servers for
        # random_pool_servers function
        Builtins.size(servers) == Builtins.size(NtpClient.random_pool_servers) &&
        # enabled means that all of needed servers are listed
        NtpClient.IsRandomServersServiceEnabled

      if Builtins.size(peers) !=
          Ops.add(Builtins.size(servers), Builtins.size(clocks))
        Builtins.y2milestone("Something else than server and clock present")
        return :complex
      end
      if random_pool_servers_enabled_only &&
          Ops.less_or_equal(Builtins.size(clocks), 1)
        Builtins.y2milestone("Simple settings with random_pool_servers")
        return :simple
      end
      if Ops.greater_than(Builtins.size(servers), 1) ||
          Ops.greater_than(Builtins.size(clocks), 1)
        Builtins.y2milestone(
          "More than one server or more than one clock present"
        )
        return :complex
      end
      clock_addr = Ops.get_string(clocks, [0, "address"], "")
      if "127.127.1.0" != clock_addr && "" != clock_addr
        Builtins.y2milestone("Non-standard clock present")
        return :complex
      end
      Builtins.y2milestone("Going simple dialog")
      :simple
    end
  end
end
