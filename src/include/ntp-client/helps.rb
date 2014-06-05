# encoding: utf-8

# File:	include/ntp-client/helps.ycp
# Package:	Configuration of ntp-client
# Summary:	Help texts of all the dialogs
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
module Yast
  module NtpClientHelpsInclude
    def initialize_ntp_client_helps(include_target)
      textdomain "ntp-client"

      # All helps are here
      @HELPS = {
        # Read dialog help 1/2
        "read"               => _(
          "<p><b><big>Initializing NTP Client Configuration</big></b><br>\nPlease wait...<br></p>"
        ) +
          # Read dialog help 2/2
          _(
            "<p><b><big>Aborting Initialization:</big></b><br>\nSafely abort the configuration utility by pressing <b>Abort</b> now.</p>"
          ),
        # Write dialog help 1/2
        "write"              => _(
          "<p><b><big>Saving NTP Client Configuration</big></b><br>\nPlease wait...<br></p>"
        ) +
          # Write dialog help 2/2
          _(
            "<p><b><big>Aborting Saving:</big></b><br>\n" +
              "Abort the save procedure by pressing  <b>Abort</b>.\n" +
              "An additional dialog will inform you whether it is safe to do so.</p>"
          ),
        # help text 1/5
        "start"              => _(
          "<p><b><big>Start NTP Daemon</big></b><br>\n" +
            "Select whether to start the NTP daemon now and on every system boot. \n" +
            "The NTP daemon resolves host names when initializing. Your\n" +
            "network connection must be started before the NTP daemon starts.</p>\n"
        )
	+
	_("Selecting <b>Synchronize without Daemon</b> the ntp daemon will not be activated. \n" +
	  "The system time will be set periodically. The interval is configurable. It is 15 minutes by default.\n " +
	  "You can change this when the system was set up."
	),
        # help text 2/5
        "chroot_environment" => _(
          "<p><b><big>Chroot Jail</big></b><br>\n" +
            "To run the NTP daemon in chroot jail, set\n" +
            "<b>Run NTP Daemon in Chroot Jail</b>. Starting any daemon in a chroot jail\n" +
            "is more secure and strongly recommended.</p>"
        ),
        "secure"             => _(
          "<p><b><big>Secure NTP Configuration</big></b><br>\n" +
            "By selecting <b>Restrict NTP Service to Configured Servers Only</b>, remote hosts will not be able to view and modify NTP settings on your \n" +
            "computer. The NTP service is restricted to servers in the <tt>/etc/ntp.conf</tt> file and to localhost.<br> \n" +
            "Access control flags can be fine-tuded in the servers overview table. This option is not available if NTP is configured via DHCP.</p>\n"
        ),
        # help text 3/5
        "config_dhcp"        => _(
          "<p><b><big>Configuring via DHCP</big></b><br>\n" +
            "To retrieve the information about NTP servers via the DHCP protocol from\n" +
            "your network server instead of setting them manually, set\n" +
            "<b>Configure NTP Daemon via DHCP</b>. Ask your network administrator if\n" +
            "the information about NTP servers is provided by the DHCP server.</p>"
        ),
        # help text 4/5
        "overview"           => _(
          "<p><b><big>Configured Servers</big></b><br>\n" +
            "To adjust NTP servers, peers, local clocks, and NTP broadcasting,\n" +
            "select the appropriate line and click <b>Edit</b>. To add a new synchronization\n" +
            "peer, click <b>Add</b>. To delete an existing synchronization peer,\n" +
            "select it and click <b>Delete</b>.</p>"
        ) +
          # help text 5/5
          _(
            "<p><b><big>Display Log</big></b></p>\n<p>To view the logs of the NTP daemon, click <b>Display Log</b>.</p>\n"
          ),
        # help text to a button
        "complex_button"     => _(
          "<p><b><big>Advanced configuration</big></b><br>\n" +
            "To configure this host to synchronize against multiple remote hosts or against\n" +
            "a locally connected clock, use <b>Advanced Configuration</b>."
        ),
        # help text 1/4
        "clock_type"         => _(
          "<p><b><big>Clock Type</big></b><br>\nSelect the driver for the clock to configure.</p>"
        ),
        # help text 2/4
        "unit_number"        => _(
          "<p><b><big>Unit Number</big></b><br>\n" +
            "If you have multiple clocks of the same type, you must set\n" +
            "<b>Unit Number</b>.</p>"
        ),
        # help text 3/4
        "device"             => _(
          "<p><b><big>Device</big></b><br>\n" +
            "To make the clock work, it may be necessary to create a special symbolic link to \n" +
            "the device to which the clock is connected. To do this, check\n" +
            "<b>Create Symlink</b> and set the <b>Device</b>. To browse for the device,\n" +
            "click <b>Browse</b>.\n" +
            "For some clock types, it is not necessary to create a symbolic link or \n" +
            "it must be created manually.</p>"
        ),
        # help text 4/4
        "fudge_button"       => _(
          "<p><b><big>Driver Calibration</big></b><br>\nTo calibrate the clock driver, click <b>Driver Calibration</b>.</p>"
        ),
        # help text 1/1, alt. 1 part 1/3
        "server_address"     => _(
          "<p><b><big>Address of the NTP Server</big></b><br>\n" +
            "To set the address of the NTP server, use the <b>Address</b> entry.\n" +
            "To find an NTP server, ask your network administrator or Internet service\n" +
            "provider.</p>"
        ) +
          # help text 1/1, alt. 1 part 2/3
          _(
            "<p><b><big>Selecting a Server</big></b><br>\n" +
              "To select an NTP server from those found in the local network\n" +
              "or from the list of known NTP servers, click <b>Select</b> and\n" +
              "choose between <b>Local NTP Server</b> and <b>Public NTP Server</b>.</p>"
          ) +
          # help text 1/1, alt. 1 part 3/3
          _(
            "<p><b><big>Testing Server Accessibility</big></b><br>\n" +
              "To test if the selected server is up and responds properly,\n" +
              "click <b>Test</b>.</p>"
          ),
        # help text 1/1, alt. 2
        "paddress"           => _(
          "<p><b><big>Address</big></b><br>\n" +
            "To set the address of the host with which to synchronize mutually,\n" +
            "use <b>Address</b>.</p>"
        ),
        # help text 1/1, alt. 3
        "bcaddress"          => _(
          "<p><b><big>Address</big></b><br>\n" +
            "To set the address to which to broadcast, use the <b>Address</b>\n" +
            "text field.</p>"
        ),
        # help text 1/1, alt. 4
        "bccaddress"         => _(
          "<p><b><big>Address</big></b><br>\n" +
            "To set the address from which to accept broadcast packets, use \n" +
            "<b>Address</b>.</p>"
        ),
        # help text 2/4, was removed

        # help text 3/4, optional
        "options"            => _(
          "<p><b><big>Options</big></b><br>\n" +
            "To fine-tune the synchronization source, enter the respective options in the\n" +
            "<b>Options</b> text field. For details, see\n" +
            "<i>/usr/share/doc/packages/ntp-doc/confopt.htm</i>.</p>\n"
        ),
        "restrict"           => _(
          "<p><b><big>Access Control Options</big></b><br>\n" +
            "Define the access control flags (<b><tt>restrict</tt></b> directive in\n" +
            "<i>/etc/ntp.conf</i>) for this server, indicating which types of actions the remote\n" +
            "host can perform on your NTP daemon. By default, it is set to <i>notrap\n" +
            "nomodify noquery</i>. This option is only available if you have checked the\n" +
            "<b>Restrict NTP Service to Configured Servers Only</b> option in\n" +
            "<b>Security Settings</b>.</p>\n"
        ),
        # help text 1/6
        "peer_types"         => _(
          "<p><b><big>Synchronization Peer Type</big></b><br>\nSelect the kind of synchronization peer to add here.</p>"
        ) +
          # help text 2/6
          _(
            "<p>To add an NTP server to which to synchronize,\nselect <b>Server</b>.</p>"
          ) +
          # help text 3/6
          _(
            "<p>To add an NTP peer to synchronize mutually, select\n<b>Peer</b>.</p>"
          ) +
          # help text 4/6
          _(
            "<p>To configure a local clock connected directly to your computer,\nselect <b>Radio Clock</b>.</p>"
          ) +
          # help text 5/6
          _(
            "<p>To broadcast time information through your network, select\n<b>Outgoing Broadcast</b>.</p>"
          ) +
          # help text 6/6
          _(
            "<p>To accept NTP packets broadcasted by other hosts on the network\nand use them for setting local time, select <b>Incoming Broadcast<b>.</p>"
          ),
        # help text 1/5
        "servers_source"     => _(
          "<p><big><b>Server Location</b></big>\n" +
            "Select if you want to find the NTP server in the local network or select\n" +
            "the NTP server from the list of known NTP servers.</p>"
        ),
        # help text 2/5
        "found_servers"      => _(
          "<p><big><b>Finding Server in the Local\n" +
            "Network</b></big><br>\n" +
            "To find NTP servers in the local network using the\n" +
            "Service Location Protocol (SLP), click <b>Lookup</b>.\n" +
            "Then select a server from the list of found servers.</p>"
        ),
        # help text 3/5
        "servers_list"       => _(
          "<p><big><b>Selecting a Public NTP Server</b></big><br>\n" +
            "Select the NTP server to use from the <b>Public NTP Servers</b> list. To display\n" +
            "NTP servers only for a particular country, select it in <b>Country</b>.</p>"
        ) +
          # help text 4/5
          _(
            "<p><big><b>Note</b></big><br>\n" +
              "The listed NTP servers may not be available from any country, but only\n" +
              "for a particular country or region.\n" +
              "Before using any NTP server from the list, ask your system administrator\n" +
              "or Internet service provider if there is an NTP server closer to you and\n" +
              "prefer this recommended server to any server from this list.\n" +
              "You may also see <i>http://www.eecis.udel.edu/~mills/ntp/servers.html</i>\n" +
              "to find an NTP server near you.</p>"
          ),
        # help text 5/5
        "selected_test"      => _(
          "<p><big><b>Testing Server Accessibility</b></big><br>\nTo test if the selected server responds properly, click <b>Test</b>.</p>"
        ),
        # help text connected with checkbox: "Use Random Server from pool.ntp.org"
        # rwalter, please, correct it ;)
        "use_random_servers" => _(
          "<p><big><b>Use Random Servers</b></big><br>\n" +
            "This service is offered by pool.ntp.org. If you select this option,\n" +
            "three different servers are added to the configuration. The server names are\n" +
            "permanent, but they change their DNS records (IPs) every hour. This means that\n" +
            "your NTP client is synchronized with different servers every hour.</p>\n"
        )
      }
    end

    # Get help to the fudge factors settings dialog
    # @return [String] the help text
    def fudgeHelp
      # help text 1/2
      _(
        "<p><big><b>Clock Driver Calibration</b></big><br>\n" +
          "The clock driver may need to be calibrated. In this dialog, various calibration\n" +
          "options can be set. The meaning of particular options depends on the particular\n" +
          "driver. Some drivers do not use all the options.</p>"
      ) +
        # help text 2/2
        _(
          "To learn more about available options, install the package\n<i>ntp-doc</i> and see <i>/usr/share/doc/packages/ntp-doc/html/refclock.htm</i>.</p>\n"
        )
    end
  end
end
