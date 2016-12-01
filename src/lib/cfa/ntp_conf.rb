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

    RECORD_ENTRIES = %w(
      server
      peer
      broadcast
      broadcastclient
      manycast
      manycastclient
      fudge
      restrict
    ).freeze

    COLLECTION_KEYS = (RECORD_ENTRIES + %w(#comment action)).freeze

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

    def raw
      PARSER.serialize(data)
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
        matcher = Matcher.new do |k, v|
          k == record.augeas[:key] &&
            v == record.augeas[:value]
        end
        @augeas_tree.delete(matcher)
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
        matcher = Matcher.new do |k, _v|
          RECORD_ENTRIES.include?(k.gsub("[]", ""))
        end
        @augeas_tree.select(matcher)
      end
    end

    # Base class to represent a general ntp entry.
    class Record
      def self.record_class(key)
        entry_type = key.gsub("[]", "")
        record_class = ["::CFA::NtpConf::", entry_type.capitalize, "Record"].join
        Kernel.const_get(record_class)
      end

      def self.new_from_augeas(augeas_entry)
        record = record_class(augeas_entry[:key]).new
        record.augeas = augeas_entry
        record
      end

      def initialize(key = nil)
        @augeas = { key: key, value: nil }
      end

      attr_accessor :augeas

      def value
        tree_value? ? tree_value.value : @augeas[:value]
      end

      def value=(value)
        if tree_value?
          tree_value.value = value
        else
          @augeas[:value] = value
        end
      end

      def comment
        return nil unless tree_value?
        tree_value.tree["#comment"]
      end

      def comment=(comment)
        create_tree_value unless tree_value?
        if comment.to_s == ""
          tree_value.tree.delete("#comment")
        else
          tree_value.tree["#comment"] = comment
        end
      end

      def ==(other)
        other.class == self.class &&
          other.augeas == augeas
      end

      alias_method :eql?, :==

      def type
        augeas[:key].gsub("[]", "")
      end

      def raw_options
        options.join(" ")
      end

      def raw_options=(raw_options)
        self.options = split_raw_options(raw_options)
      end

      private

      def tree_value?
        @augeas[:value].is_a?(AugeasTreeValue)
      end

      def tree_value
        tree_value? ? @augeas[:value] : nil
      end

      def create_tree_value
        @augeas[:value] = AugeasTreeValue.new(AugeasTree.new, @augeas[:value])
      end

      def split_raw_options(raw_options)
        raw_options.to_s.strip.gsub(/\s+/, " ").split(" ")
      end

      def augeas_options
        tree_value.tree.select(options_matcher)
      end

      def options_matcher
        Matcher.new { |k, _v| !k.include?("#comment") }
      end
    end

    # Base class to represent a ntp command entry, as
    # server, peer, broadcast, etc.
    class CommandRecord < Record
      def options
        return [] unless tree_value?
        augeas_options.map { |option| option[:key] }
      end

      def options=(options)
        create_tree_value unless tree_value?
        tree_value.tree.delete(options_matcher)
        options.each { |option| tree_value.tree.add(option, nil) }
      end
    end

    # class to represent a ntp server entry.
    #   For example:
    #     server 0.opensuse.pool.ntp.org iburst
    class ServerRecord < CommandRecord
      def initialize
        super("server[]")
      end
    end

    # class to represent a ntp peer entry.
    #   For example:
    #     peer 128.100.0.45
    class PeerRecord < CommandRecord
      def initialize
        super("peer[]")
      end
    end

    # class to represent a ntp broadcast entry.
    #   For example:
    #     broadcast 128.100.0.45
    class BroadcastRecord < CommandRecord
      def initialize
        super("broadcast[]")
      end
    end

    # class to represent a ntp broadcastclient entry.
    class BroadcastclientRecord < CommandRecord
      def initialize
        super("broadcastclient[]")
      end
    end

    # class to represent a ntp fudge entry.
    #   For example:
    #     fudge  127.127.1.0 stratum 10
    class FudgeRecord < CommandRecord
      def initialize
        super("fudge[]")
      end

      def options
        return {} unless tree_value?
        augeas_options.each_with_object({}) do |option, opts|
          opts[option[:key]] = option[:value]
        end
      end

      def options=(options)
        create_tree_value unless tree_value?
        tree_value.tree.delete(options_matcher)
        options.each { |k, v| tree_value.tree.add(k, v) }
      end

      def raw_options
        options.to_a.flatten.join(" ")
      end

      def raw_options=(raw_options)
        options = split_raw_options(raw_options)
        self.options = options.each_slice(2).to_a.to_h
      end
    end

    # class to represent a ntp restrict entry.
    #   For example:
    #     restrict -4 default notrap nomodify nopeer noquery
    class RestrictRecord < Record
      def initialize
        super("restrict[]")
      end

      def options
        return [] unless tree_value?
        augeas_options.map { |option| option[:value] }
      end

      def options=(options)
        create_tree_value unless tree_value?
        tree_value.tree.delete(options_matcher)
        options.each { |option| tree_value.tree.add("action[]", option) }
      end

      private

      def options_matcher
        Matcher.new { |k, _v| k.include?("action") }
      end
    end
  end
end
