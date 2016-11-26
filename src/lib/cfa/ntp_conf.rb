require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

module CFA
  class NtpConf < ::CFA::BaseModel
    PARSER = CFA::AugeasParser.new("ntp.lns")
    DEFAULT_PATH = "/etc/ntp.conf".freeze
    COMMAND_RECORDS = ["server", "peer", "broadcast", "manycastclient", "multicastclient", "manycastserver"].freeze

    attributes(
      driftfile: "driftfile",
      logfile: "logfile",
      keys: "keys",
      requestkey: "requestkey",
      controlkey: "controlkey"
    )
      
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

    class RecordCollection
      def initialize(record_class, augeas_collection) 
        @record_class = record_class
        @augeas_collection = augeas_collection
      end

      def each
        @augeas_collection.each do |augeas_value| 
          yield @record_class.new_from_augeas(augeas_value)
        end
      end

      def map
        @augeas_collection.map do |augeas_value| 
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
        matcher = CFA::Matcher.new {|k, v| v == old_record.to_augeas}
        placer = CFA::ReplacePlacer.new(matcher)
        @augeas_collection.add(new_record.to_augeas, placer)
      end
    end

    class Record
      def self.new_from_augeas(augeas_value)
        record = self.new
        record.send(:set_attributes, augeas_value)
        record
      end

      def initialize(value: nil, tree_data: [])
        @value = value
        @tree_data = tree_data
      end

      attr_reader :value

      def comment
        comment = @tree_data.select {|d| d[:key] == "#comment"}.first
        comment[:value] if !comment.nil?
      end

      def to_augeas
        return value if @tree_data.empty?
        CFA::AugeasTreeValue.new(create_tree, value)
      end

      private

      def set_attributes(augeas_value)
        case augeas_value
        when CFA::AugeasTreeValue
          @value = augeas_value.value
          @tree_data = augeas_value.tree.data
        else
          @value = augeas_value
        end
      end

      def add_comment(comment)
        @tree_data << {key: "#comment", value: comment} if !comment.nil?
      end

      def create_tree
        tree = CFA::AugeasTree.new
        @tree_data.each {|d| tree.add(d[:key], d[:value])}
        tree
      end
    end

    class CommandRecord < Record
      def initialize(value: nil, options: [], comment: nil)
        super(value: value)
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

    class RestrictRecord < Record
      def initialize(value: nil, actions: [], comment: nil)
        super(value: value)
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
