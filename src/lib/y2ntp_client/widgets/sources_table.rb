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
    # Table displaying list of defined NTP sources. It displays its type and address.
    class SourcesTable < CWM::Table
      attr_reader :sources

      SOURCES = {
        pool:   "Pool".freeze,
        server: "Server".freeze
      }.freeze

      # @param sources [Hash<String, Symbol>] hash of ntp sources address (ip or url)
      #                                       and type (pool or server)
      def initialize(sources = {})
        super()
        textdomain "ntp-client"

        # TODO: validation of the input
        @sources = sources
      end

      def header
        [
          _("Type"),
          _("Address")
        ]
      end

      def items
        # <id, source-type, source-address>
        @sources.map { |a, t| [a, SOURCES[t], a] }
      end

      def sources=(sources)
        @sources = sources

        change_items(items)
        items&.each_with_object({}) { |i, acc| acc[i[1]] = i[2] }
      end

      # Adds one item into table's content
      #
      # @param item [Array] a table item in array format (<id, column1 value, column2 value, ...)
      def add_item(item)
        change_items(items << item)
      end

      # Removes one item from table's content
      #
      # @param id [any] id of table's item to remove
      def remove_item(id)
        updated_items = items.delete_if { |i| i[0] == id }
        change_items(updated_items)
      end
    end

    # A button for adding an item into @see SourcesTable
    class SourcesAdd < CWM::PushButton
      def initialize
        super
        textdomain "ntp-client"
      end

      def label
        _("Add")
      end

      def handle
        nil
      end
    end

    # A button for removing an item from @see SourcesTable
    class SourcesRemove < CWM::PushButton
      def initialize
        super
        textdomain "ntp-client"
      end

      def label
        _("Remove")
      end

      def handle
        nil
      end
    end

    # A ComboBox containing varius supported types of NTP Sources
    class SourcesType < CWM::ComboBox
      def initialize
        super
        textdomain "ntp-client"
      end

      def label
        _("Source Type")
      end

      def items
        [
          [:pool, _("Pool")],
          [:server, _("Server")]
        ]
      end
    end
  end
end
