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
    DEFAULT_PATH = "/etc/ntp.conf".freeze
    SIMPLE_SETTINGS = ["logfile", "driftfile"].freeze
    AUTH_COMMANDS = ["trustedkey", "requestkey", "controlkey", "keys"].freeze
    COMMAND_RECORDS = ["server", "peer", "broadcast", "manycastclient", "multicastclient", "manycastserver"].freeze

    def self.ntp_attributes(*attrs)
      attrs.each do |attr|
        define_method(attr) {get_attribute(attr.to_s)}
        define_method("#{attr}=") {|record| set_attribute(attr.to_s, record)}
        define_method("delete_#{attr}") {delete_attribute(attr.to_s)}
      end
    end

    ntp_attributes :driftfile, :logfile, :keys, :requestkey, :controlkey
      
    def initialize(path: DEFAULT_PATH, file_handler: nil)
      super(PARSER, path, file_handler: file_handler)
    end

    def servers
      RecordCollection.new(ServerRecord, data.collection("server"))
    end

    def peers
      RecordCollection.new(PeerRecord, data.collection("peer"))
    end

    def restricts
      RecordCollection.new(RestrictRecord, data.collection("restrict"))
    end

    private

    def get_attribute(name)
      return nil if data[name].nil? 
      AttributeRecord.new_from_augeas(data[name])
    end

    def set_attribute(name, record)
      data[name] = record.to_augeas
    end

    def delete_attribute(name)
      data.delete(name)
    end

    # class to manage a collection of some ntp entries, as
    # server, restrict, peer, etc.
    #   For example:
    #     server 0.opensuse.pool.ntp.org iburst
    #     server 1.opensuse.pool.ntp.org iburst
    #     server 2.opensuse.pool.ntp.org iburst
    #     server 3.opensuse.pool.ntp.org iburst
    class RecordCollection
      include Enumerable

      def initialize(record_class, augeas_collection) 
        @record_class = record_class
        @augeas_collection = augeas_collection
      end

      def each
        @augeas_collection.each do |augeas_value| 
          yield @record_class.new_from_augeas(augeas_value)
        end
      end

      def add(record)
        @augeas_collection.add(record.to_augeas)
      end

      def delete(record)
        @augeas_collection.delete(record.to_augeas)
      end

      def replace(old_record, new_record)
        return if !self.include? old_record
        matcher = CFA::Matcher.new {|k, v| v == old_record.to_augeas}
        placer = CFA::ReplacePlacer.new(matcher)
        @augeas_collection.add(new_record.to_augeas, placer)
      end

      def empty?
        @augeas_collection.empty?
      end

      def ==(other)
        other.to_a == self.to_a
      end

    end

    # class to represent a general entry of the file.
    class Record
      def initialize(value: nil, tree_data: [])
        @value = value
        @tree_data = tree_data
      end

      def self.new_from_augeas(augeas_value)
        value, tree_data = self.parse_augeas(augeas_value)
        record = self.new
        record.send(:add_value, value)
        record.send(:add_tree_data, tree_data)
        record
      end

      attr_reader :value

      def to_augeas
        create_augeas
      end

      def comment
        comment = @tree_data.select {|d| d[:key] == "#comment"}.first
        comment[:value] if !comment.nil?
      end

      def ==(other)
        other.class == self.class &&
        other.value == self.value &&
        other.tree_data == self.tree_data
      end

      alias :eq? :==

      protected

      attr_reader :tree_data

      private

      def add_value(value)
        @value = value
      end

      def add_tree_data(tree_data)
        @tree_data = tree_data
      end

      def add_comment(comment)
        @tree_data << {key: "#comment", value: comment} if !comment.nil?
      end

      def self.parse_augeas(augeas_value)
        case augeas_value
        when CFA::AugeasTreeValue
          value = augeas_value.value
          tree_data = augeas_value.tree.data
        else
          value = augeas_value
          tree_data = []
        end
        [value, tree_data]
      end

      def create_augeas
        return value if @tree_data.empty?
        tree = CFA::AugeasTree.new
        @tree_data.each {|d| tree.add(d[:key], d[:value])}
        CFA::AugeasTreeValue.new(tree, value)
      end
    end

    # class to represent a key-value ntp entry.
    #   For example:
    #     logfile /var/log/ntp
    class AttributeRecord < Record
      def initialize(value: nil, comment: nil)
        super()
        add_value(value)
        add_comment(comment)
      end
    end

    # class to represent ntp command entries, as
    # server, peer.
    #   For example:
    #     server 0.opensuse.pool.ntp.org iburst
    class CommandRecord < Record
      def initialize(value: nil, options: [], comment: nil)
        super()
        add_value(value)
        add_options(options)
        add_comment(comment)
      end

      def options
        options = @tree_data.select {|d| d[:key] != "#comment"}
        options.map {|option| option[:key]}
      end

      private

      def add_options(options)
        @tree_data += options.map {|option| {key: option, value: nil}}
      end
    end

    class ServerRecord < CommandRecord
    end

    class PeerRecord < CommandRecord
    end

    # class to represent ntp restrict entries.
    #   For example:
    #     restrict -4 default notrap nomodify nopeer noquery
    class RestrictRecord < Record
      def initialize(value: nil, actions: [], comment: nil)
        super()
        add_value(value)
        add_actions(actions)
        add_comment(comment)
      end

      def actions
        actions = @tree_data.select {|d| d[:key] == "action[]"}
        actions.map {|action| action[:value]}
      end

      private

      def add_actions(actions)
        @tree_data += actions.map {|action| {key: "action[]", value: action}}
      end
    end
  end
end
