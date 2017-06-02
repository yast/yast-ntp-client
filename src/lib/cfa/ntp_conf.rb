require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"

module CFA
  # class representings /etc/ntp.conf file model. It provides helper to manipulate
  # with file. It uses CFA framework and Augeas parser.
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/BaseModel
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/AugeasParser
  #
  # In NTP files some keys can be present multiple times.
  #
  # For example:
  #
  # server 1.pool.ntp.org iburst
  # server 2.pool.ntp.org
  # server 127.127.1.0
  # fudge 127.127.1.0 stratum 10
  # peer 128.100.0.45
  # peer 192.168.1.30
  #
  # Order of lines is not important, except for the
  # fudge option that should immediately follow
  # appropriate "server" option.
  #
  # Important keys (that are to be read and written) are
  # server, peer, fudge, broadcast and broadcastclient.
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
      driftfile
      logfile
      keys
      trustedkey
      requestkey
      controlkey
    ).freeze

    COLLECTION_KEYS = (RECORD_ENTRIES + ["action"]).freeze

    def initialize(file_handler: nil)
      super(PARSER, PATH, file_handler: file_handler)
    end

    # Loads and fixes AugeasElement keys.
    #
    # AugeasParser returns collection entries with
    # key ending in '[]', for example 'server[]'.
    #
    # If only exists one entry of the collection, parser
    # return key without '[]'.
    #
    # For example:
    #
    # server 1.pool.ntp.org iburst
    # server 2.pool.ntp.org
    # peer 128.100.0.45
    #
    # In this case, key for peer entry is 'peer'.
    # It is necessary to add '[]' to avoid possible
    # write issues when more entries of that type
    # are added.
    def load
      super
      fix_keys(data)
    end

    def save
      records.each do |r|
        next unless r.augeas[:multiline]

        comments = r.augeas[:multiline].split("\n")
        matcher = Matcher.new(key: r.augeas[:key], value_matcher: r.augeas[:value])
        placer = BeforePlacer.new(matcher)
        comments.each do |c|
          data.add("#comment[]", c, placer)
        end
      end
      super
    end

    # Obtains a collection that represents the
    # entries of the file.
    # @return [CollectionRecord] collection to
    #   manipulate ntp entries.
    #
    # The collection preserves the order of the
    # ntp entries in the file and only contains the
    # entries of interest (see RECORD_ENTRIES).
    def records
      @records ||= RecordCollection.new(data)
    end

    # Obtains raw content of the file.
    # @return [String]
    def raw
      PARSER.serialize(data)
    end

  private

    def fix_keys(tree)
      tree.data.each do |entry|
        entry[:key] << "[]" if COLLECTION_KEYS.include?(entry[:key])
        fix_keys(entry[:value].tree) if entry[:value].is_a?(AugeasTreeValue)
      end
    end

    # class to manage ntp entries as a collection.
    #
    # The collection preserves the order of the
    # ntp entries in the file and only contains the
    # entries of interest (see RECORD_ENTRIES).
    #
    # For example:
    #
    # server 1.pool.ntp.org iburst
    # server 2.pool.ntp.org
    # peer 128.100.0.45
    #
    # The collection contents a derived Record class
    # object for each line. In this case, two
    # ServerRecord and a PeerRecord.
    class RecordCollection
      include Enumerable

      def initialize(augeas_tree)
        @augeas_tree = augeas_tree
      end

      # Iterates the elements of the collection (@see Array#each).
      # @yield [Record] gives a record of the collection
      def each(&block)
        record_entries.each(&block)
      end

      # Get last record in collection
      def last
        record_entries.last
      end

      # Adds a new Record object to the collection.
      # @note argument is not member of collection and instead new instance
      # is created from its augeas content.
      # So for later modification please get new instance with `#last`.
      # @param [Record] record
      def <<(record)
        @augeas_tree.add(record.augeas[:key], record.augeas[:value])
        # TODO: nasty workaround to survive multiline key with long comments
        @augeas_tree.all_data.last[:multiline] = record.augeas[:multiline]
        reset_cache
      end

      # Removes a Record object from the collection.
      # @param [Record] record
      def delete(record)
        matcher = Matcher.new(
          key:           record.augeas[:key],
          value_matcher: record.augeas[:value]
        )
        @augeas_tree.delete(matcher)
        reset_cache
      end

      # Removes all records that satisfy a condition.
      # @yield [Record] gives a record of the collection
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

      def reset_cache
        @record_entries = nil
      end

      def record_entries
        return @record_entries if @record_entries
        matcher = Matcher.new do |k, _v|
          RECORD_ENTRIES.include?(k.gsub("[]", ""))
        end
        @record_entries = @augeas_tree.select(matcher).map do |e|
          Record.new_from_augeas(e)
        end
      end
    end

    # Base class to represent a general ntp entry.
    #
    # This class is an AugeasElement wrapper. A Record
    # has a value, and could also contains a comment and
    # options. All its modifications are directly saved
    # into augeas tree.
    #
    # Each ntp entry type has different interpretation
    # for its options in the AugeasElement. For each one,
    # a Record subclass is created.
    class Record
      # Creates the corresponding subclass object according
      # to its AugeasElement key.
      # @param [String] key
      def self.new_from_augeas(augeas_entry)
        record_class(augeas_entry[:key]).new(augeas_entry)
      end

      # Returns the corresponding subclass
      # @param [string] key
      def self.record_class(key)
        entry_type = key.gsub("[]", "")
        record_class = "::CFA::NtpConf::#{entry_type.capitalize}Record"
        Kernel.const_get(record_class)
      end

      def initialize(augeas = nil)
        augeas ||= create_augeas
        @augeas = augeas
        @multiline_comment = ""
      end

      attr_reader :augeas

      def value
        tree_value? ? tree_value.value : @augeas[:value]
      end

      def value=(value)
        if tree_value?
          tree_value.value = value
        else
          @augeas[:value] = value
          @augeas[:operation] ||= :add
          @augeas[:operation] = :modify if @augeas[:operation] != :add
        end
      end

      def comment
        return augeas[:mutline] if augeas[:multiline]
        return nil unless tree_value?
        tree_value.tree["#comment"]
      end

      # Comment is saved literally, so be sure that
      # it is prepended by '#'
      def comment=(comment)
        ensure_tree_value
        if comment.to_s == ""
          tree_value.tree.delete("#comment")
          augeas[:multiline] = nil
        # backward compatibility for autoyast which allows multiline comments
        elsif comment.include?("\n")
          augeas[:multiline] = comment
        else
          tree_value.tree["#comment"] = comment
          augeas[:multiline] = nil
        end
      end

      def options
        raise NotImplementedError,
          "Subclasses of #{Module.nesting.first} must override #{__method__}"
      end

      def options=(_options)
        raise NotImplementedError,
          "Subclasses of #{Module.nesting.first} must override #{__method__}"
      end

      def ==(other)
        other.class == self.class && value == other.value
      end

      alias_method :eql?, :==

      def type
        @augeas[:key].gsub("[]", "")
      end

      # Returns an String representing the options
      def raw_options
        options.join(" ")
      end

      # Sets options from a String
      def raw_options=(raw_options)
        self.options = split_raw_options(raw_options)
      end

    protected

      def create_augeas
        { key: self.class.const_get("AUGEAS_KEY"), value: nil }
      end

      def tree_value?
        @augeas[:value].is_a?(AugeasTreeValue)
      end

      def tree_value
        @augeas[:value]
      end

      def ensure_tree_value
        @augeas[:value] = AugeasTreeValue.new(
          AugeasTree.new,
          @augeas[:value]
        ) unless tree_value?
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

    # class to represent a ntp command record entry. There is a
    # subclass for server, peer, broadcast and broacastclient.
    class CommandRecord < Record
      def options
        return [] unless tree_value?
        augeas_options.map { |option| option[:key] }
      end

      def options=(options)
        ensure_tree_value
        tree_value.tree.delete(options_matcher)
        options.each { |option| tree_value.tree.add(option, nil) }
      end
    end

    # class to represent a driftfile entry.
    # For example:
    #   driftfile /var/lib/ntp/drift/ntp.drift
    class DriftfileRecord < CommandRecord
      AUGEAS_KEY = "driftfile[]".freeze
    end

    # class to represent a logfile entry.
    # For example:
    #   logfile /var/log/ntp
    class LogfileRecord < CommandRecord
      AUGEAS_KEY = "logfile[]".freeze
    end

    # class to represent a keys entry.
    # For example:
    #   keys /etc/ntp.keys
    class KeysRecord < CommandRecord
      AUGEAS_KEY = "keys[]".freeze
    end

    # class to represent a trustedkey entry.
    # For example:
    #   trustedkey 1
    class TrustedkeyRecord < CommandRecord
      AUGEAS_KEY = "trustedkey[]".freeze

      def initialize(augeas = nil)
        super
        ensure_tree_value
        tree_value.value = nil
      end

      # for trustedkey it is subtree of keys
      def value
        return [] unless tree_value?
        key_matcher = CFA::Matcher.new { |k, v| k == "key" || k == "key[]" }
        keys = tree_value.tree.select(key_matcher)
        keys.map { |option| option[:value] }.join(" ")
      end

      def value=(options)
        values = options.split("\s")
        ensure_tree_value
        tree_value.tree.delete("key")
        tree_value.tree.delete("key[]")
        values.each { |value| tree_value.tree.add("key[]", value) }
      end

      # here key is actually value and not option
      def options_matcher
        Matcher.new { |k, _v| !k.include?("#comment") && !k.include?("key") }
      end
    end

    # class to represent a requestkey entry.
    # For example:
    #   requestkey 1
    class RequestkeyRecord < CommandRecord
      AUGEAS_KEY = "requestkey[]".freeze
    end

    # class to represent a controlkey entry.
    # For example:
    #   controlkey 1
    class ControlkeyRecord < CommandRecord
      AUGEAS_KEY = "controlkey[]".freeze
    end

    # class to represent a ntp server entry.
    # For example:
    #   server 0.opensuse.pool.ntp.org iburst
    class ServerRecord < CommandRecord
      AUGEAS_KEY = "server[]".freeze
    end

    # class to represent a ntp peer entry.
    # For example:
    #   peer 128.100.0.45
    class PeerRecord < CommandRecord
      AUGEAS_KEY = "peer[]".freeze
    end

    # class to represent a ntp broadcast entry.
    # For example:
    #   broadcast 128.100.0.45
    class BroadcastRecord < CommandRecord
      AUGEAS_KEY = "broadcast[]".freeze
    end

    # class to represent a ntp broadcastclient entry.
    class BroadcastclientRecord < CommandRecord
      AUGEAS_KEY = "broadcastclient[]".freeze
    end

    # class to represent a ntp fudge entry.
    #
    # For example:
    #   fudge  127.127.1.0 stratum 10
    #
    # Fudge entry has its own options interpretation.
    class FudgeRecord < CommandRecord
      AUGEAS_KEY = "fudge[]".freeze

      def options
        return {} unless tree_value?
        augeas_options.each_with_object({}) do |option, opts|
          opts[option[:key]] = option[:value]
        end
      end

      def options=(options)
        ensure_tree_value
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
    #
    # For example:
    #   restrict -4 default notrap nomodify nopeer noquery
    #
    # Restrict entry has its own options interpretation.
    class RestrictRecord < Record
      AUGEAS_KEY = "restrict[]".freeze

      def options
        return [] unless tree_value?
        res = augeas_options.map { |option| option[:value] }
        res.shift if old_lens?

        res
      end

      def options=(options)
        # backward compatibility with old lens that set value ip restriction
        # instead of address
        if old_lens?
          options = options.dup
          address = augeas_options.map { |option| option[:value] }.first
          options.unshift(address) if address
        end

        ensure_tree_value
        tree_value.tree.delete(options_matcher)
        options.each { |option| tree_value.tree.add("action[]", option) }
      end

      alias_method :orig_value, :value
      def value
        old_lens? ? augeas_options.map { |option| option[:value] }.first : orig_value
      end

      def value=(value)
        if old_lens?
          holder = tree_value.tree.select(options_matcher).first
          holder[:value] = value
          holder[:operation] = :modify
        else
          super
        end
      end

    private

      def options_matcher
        Matcher.new { |k, _v| k.include?("action") }
      end

      # backward compatibility with old lens that set value ip restriction
      # instead of address
      # for old lens data can look like:
      #   line in configuration file:
      #     restrict -4 default nofail
      #   augeas tree:
      #     key:       restrict
      #     value:     -4
      #     action[1]: default
      #     action[2]: nofail
      #
      #   line in configuration file:
      #     restrict default nofail
      #   augeas tree:
      #     key:       restrict
      #     value:     default
      #     action[1]: nofail
      #
      # with new lens value is always address like:
      #   line in configuration file:
      #     restrict -4 default nofail
      #   augeas tree:
      #     key:       restrict
      #     value:     default
      #     action[1]: nofail
      #     ipv4:      nil
      #
      #   line in configuration file:
      #     restrict default nofail
      #   augeas tree:
      #     key: restrict
      #     value: default
      #     action[1]: nofail
      def old_lens?
        ["-6", "-4"].include?(orig_value)
      end
    end
  end
end
