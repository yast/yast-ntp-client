# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "cwm/table"
require "cwm/widget"

module Y2NtpClient
  module Widgets
    class SourcesTable < CWM::Table
      # @param sources [Array<String>] array of ntp sources (ip or url)
      def initialize(sources = [])
        textdomain "ntp-client"

        # TODO: kind of validarion pre-processing
        # <id, source-type, source-address>
        @sources = sources.map { |s| [s, "", s] }
      end

      def header
        [
          _("Type"),
          _("Address"),
        ]
      end

      def items
        @sources || []
      end

      def config
        Yast::Lan.yast_config
      end
    end

    class SourcesAdd < CWM::PushButton
      def initialize
        textdomain "ntp-client"
      end

      def label
        _("Add")
      end

      def handle
        nil
      end
    end

    class SourcesRemove < CWM::PushButton
      def initialize
        textdomain "ntp-client"
      end

      def label
        _("Remove")
      end

      def handle
        nil
      end
    end

    class SourcesType < CWM::ComboBox
      def initialize
        textdomain "ntp-client"
      end

      def label
        _("Source Type")
      end

      def items
        [
          [ "pool", _("Pool") ],
          [ "server", _("Server") ]
        ]
      end
    end
  end
end
