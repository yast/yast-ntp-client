require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

module CFA
  # class representings /etc/ntp.conf file model. It provides helper to manipulate
  # with file. It uses CFA framework and Augeas parser.
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/BaseModel
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/AugeasParser
  class NtpConf < ::CFA::BaseModel
    PARSER = CFA::AugeasParser.new("ntp.lns")
    PATH = "/etc/ntp.conf".freeze
    COLLECTION_KEYS = %W(
      server
      peer
      broadcast
      manycastclient
      multicastclient
      manycastserver
      fudge
      restrict
      #comment
      action
    ).freeze

    def initialize(file_handler: nil)
      super(PARSER, PATH, file_handler: file_handler)
    end

    def load
      super
      fix_keys
    end

    def records
      RecordCollection.new(data)
    end

    private

    def fix_keys
      fix_collection_keys(data.data)
      data.data.each do |entry|
        if entry[:value].is_a?(AugeasTreeValue)
          fix_collection_keys(entry[:value].tree.data)  
        end
      end
    end

    def fix_collection_keys(entries)
      entries.each do |entry|
        if COLLECTION_KEYS.include?(entry[:key])
          entry[:key] += "[]" unless entry[:key] =~ /.*\[\]$/
        end
      end
    end

    # class to manage ntp entries
    class RecordCollection
      include Enumerable

      RECORD_ENTRIES = %W(
        server
        peer
        broadcast
        manycastclient
        multicastclient
        manycastserver
        fudge
        restrict
        #comment
      ).freeze

      def initialize(augeas_tree)
        @augeas_tree = augeas_tree
      end

      def each
        record_entries.each do |augeas_element|
          yield Record.new_from_augeas(augeas_element)
        end
      end

      def add(record)
        @augeas_tree.data << record.augeas
      end

      alias_method :<<, :add

      def delete(record)
        @augeas_tree.delete_if { |entry| entry == record.augeas }
      end

      def delete_if(&block)
        records = select(&block)
        records.each { |record| delete(record) }
      end

      def empty?
        count == 0
      end

      def ==(other)
        other.to_a == to_a
      end

      private

      def record_entries
        @augeas_tree.data.select do |d| 
          RECORD_ENTRIES.include?(d[:key].gsub("[]", ""))
        end
      end
    end

    # class to represent a general entry of the file.
    class Record
      def self.record_class(key)
        case key
        when /server/ then ServerRecord
        when /peer/ then PeerRecord
        when /broadcast/ then BroadcastRecord
        when /broadcastclient/ then BroadcastclientRecord
        when /manycast/ then ManycastRecord
        when /manycastclient/ then ManycastclientRecord
        when /fudge/ then FudgeRecord
        when /restrict/ then RestrictRecord
        when /comment/ then CommentRecord
        end
      end

      def initialize(key = nil)
        @augeas = { key: key, value: nil }
      end

      attr_accessor :augeas

      def self.new_from_augeas(augeas_entry)
        record = record_class(augeas_entry[:key]).new
        record.augeas = augeas_entry
        record
      end

      def value
        has_tree_value? ? tree_value.value : @augeas[:value]
      end

      def value=(value)
        if has_tree_value?
          tree_value.value = value
        else
          @augeas[:value] = value
        end
      end

      def comment
        return nil unless has_tree_value?
        tree_value.tree["#comment"]
      end

      def comment=(comment)
        create_tree_value unless has_tree_value?
        tree_value.tree["#comment"] = comment
      end

      def ==(other)
        other.class == self.class && 
          other.augeas == augeas
      end

      alias_method :eql?, :==

      private

      def has_tree_value?
        @augeas[:value].is_a?(AugeasTreeValue)
      end

      def tree_value
        has_tree_value? ? @augeas[:value] : nil
      end

      def create_tree_value
        @augeas[:value] = AugeasTreeValue.new(AugeasTree.new, @augeas[:value])
      end
    end

    class CommentRecord < Record
      def initialize
        super("#comment[]")
      end
    end

    # class to represent ntp command entries, as
    # server, peer.
    #   For example:
    #     server 0.opensuse.pool.ntp.org iburst
    class CommandRecord < Record
      def options
        return [] unless has_tree_value?
        current_options = tree_value.tree.data.reject { |d| d[:key].include?("#comment") }
        current_options.map { |option| option[:key] }
      end

      def options=(options)
        create_tree_value unless has_tree_value?
        tree_value.tree.data.reject! { |d| d[:key] != "#comment" }
        options.each { |option| tree_value.tree.add(option, nil) }
      end
    end

    class ServerRecord < CommandRecord
      def initialize
        super("server[]")
      end
    end

    class PeerRecord < CommandRecord
      def initialize
        super("peer[]")
      end
    end

    class FudgeRecord < CommandRecord
      def initialize
        super("fudge[]")
      end

      def options
        return {} unless has_tree_value?
        current_options = tree_value.tree.data.reject { |d| d[:key].to_s.include?("#comment") }
        current_options.each_with_object({}) do |option, opts|
          opts[option[:key]] = option[:value]
        end
      end

      def options=(options)
        create_tree_value unless has_tree_value?
        tree_value.tree.data.reject! { |d| d[:key] != "#comment" }
        options.each { |k, v| tree_value.tree.add(k, v) }
      end
    end

    # class to represent ntp restrict entries.
    #   For example:
    #     restrict -4 default notrap nomodify nopeer noquery
    class RestrictRecord < Record
      def initialize
        super("restrict[]")
      end

      def actions
        return [] unless has_tree_value?
        current_actions = tree_value.tree.data.select { |d| d[:key] == "action[]" }
        current_actions.map { |action| action[:value] }
      end

      def actions=(actions)
        create_tree_value unless has_tree_value?
        tree_value.tree.data.reject! { |d| d[:key].include?("action") }
        actions.each { |action| tree_value.tree.add("action[]", action) }
      end
    end
  end
end
