# encoding: utf-8

# File:	include/ntp-client/wizards.ycp
# Package:	Configuration of ntp-client
# Summary:	Wizards definitions
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
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

    # Complex workflow of the ntp-client configuration
    # @return sequence result
    def ComplexSequence
      aliases = {
        "main"                 => lambda { MainDialog() },
        "type_select"          => lambda { TypeSelectDialog() },
        "server"               => lambda { ServerDialog() },
        "server_select_local"  => lambda { LocalServerSelectionDialog() },
        "server_select_public" => lambda { PublicServerSelectionDialog() },
        "peer"                 => lambda { PeerDialog() },
        "clock"                => lambda { RadioDialog() },
        "fudge"                => lambda { FudgeDialog() },
        "bcast"                => lambda { BCastDialog() },
        "bcastclient"          => lambda { BCastClientDialog() },
        "store_record"         => [lambda { StoreRecord() }, true]
      }

      sequence = {
        "ws_start"             => "main",
        "main"                 => {
          abort:       :abort,
          next:        :next,
          peer:        "peer",
          server:      "server",
          clock:       "clock",
          bcast:       "bcast",
          bcastclient: "bcastclient",
          add:         "type_select"
        },
        "type_select"          => {
          abort:       :abort,
          peer:        "peer",
          server:      "server",
          clock:       "clock",
          bcast:       "bcast",
          bcastclient: "bcastclient"
        },
        "peer"                 => { abort: :abort, next: "store_record" },
        "server"               => {
          abort:         :abort,
          next:          "store_record",
          select_local:  "server_select_local",
          select_public: "server_select_public"
        },
        "server_select_local"  => {
          abort: :abort,
          next:  "server",
          back:  "server"
        },
        "server_select_public" => {
          abort: :abort,
          next:  "server",
          back:  "server"
        },
        "clock"                => {
          abort: :abort,
          next:  "store_record",
          fudge: "fudge"
        },
        "fudge"                => { abort: :abort, next: "clock" },
        "bcast"                => { abort: :abort, next: "store_record" },
        "bcastclient"          => { abort: :abort, next: "store_record" },
        "store_record"         => { abort: :abort, next: "main" }
      }

      ret = Sequencer.Run(aliases, sequence)

      ret
    end

    # The simple workflow for the NTP client
    # @return sequence result
    def SimpleSequence
      NtpClient.selected_record = {
        "type"    => "__clock",
        "address" => "127.127.3.2"
      }

      aliases = {
        "switcher"             => [lambda { SelectConfigType() }, true],
        "simple_pre"           => [lambda { SimpleDialogPrepare() }, true],
        "simple"               => lambda { SimpleDialog() },
        "simple_post"          => [lambda { SimpleDialogFinish() }, true],
        "server_select_local"  => lambda { LocalServerSelectionDialog() },
        "server_select_public" => lambda { PublicServerSelectionDialog() },
        "complex"              => lambda { ComplexSequence() }
      }

      sequence = {
        "ws_start"             => "switcher",
        "switcher"             => {
          simple:  "simple_pre",
          complex: "complex"
        },
        "simple_pre"           => { abort: :abort, next: "simple" },
        "simple"               => {
          abort:         :abort,
          next:          "simple_post",
          complex:       "complex",
          select_local:  "server_select_local",
          select_public: "server_select_public"
        },
        "simple_post"          => { abort: :abort, next: :next },
        "server_select_local"  => {
          abort: :abort,
          next:  "simple",
          back:  "simple"
        },
        "server_select_public" => {
          abort: :abort,
          next:  "simple",
          back:  "simple"
        },
        "complex"              => { abort: :abort, next: :next }
      }

      ret = Sequencer.Run(aliases, sequence)

      ret
    end

    # Whole configuration of ntp-client
    # @return sequence result
    def NtpClientSequence
      aliases = {
        "read"  => [lambda { ReadDialog() }, true],
        "main"  => lambda { SimpleSequence() },
        "write" => [lambda { WriteDialog() }, true]
      }

      sequence = {
        "ws_start" => "read",
        "read"     => { abort: :abort, next: "main" },
        "main"     => { abort: :abort, next: "write" },
        "write"    => { abort: :abort, next: :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("ntp-client")
      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret
    end

    # Autoyast configuration of ntp-client
    # @return sequence result
    def NtpClientAutoSequence
      aliases = { "main" => lambda { ComplexSequence() } }

      sequence = {
        "ws_start" => "main",
        "main"     => { abort: :abort, next: :next }
      }

      # dialog caption
      caption = _("NTP Client Configuration")
      # label
      contents = Label(_("Initializing ..."))

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("ntp-client")
      Wizard.SetContentsButtons(
        caption,
        contents,
        "",
        Label.BackButton,
        Label.NextButton
      )

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret
    end
  end
end
