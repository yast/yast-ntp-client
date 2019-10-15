require "cfa/base_model"
require "cfa/augeas_parser"
require "cfa/matcher"
require "cfa/placer"

module CFA
  # class representings /etc/chrony.conf file model. It provides helper to manipulate
  # with file. It uses CFA framework and Augeas parser.
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/BaseModel
  # @see http://www.rubydoc.info/github/config-files-api/config_files_api/CFA/AugeasParser
  #
  class ChronyConf < ::CFA::BaseModel
    PATH = "/etc/chrony.conf".freeze

    def initialize(file_handler: nil)
      super(CFA::AugeasParser.new("chrony.lns"), PATH, file_handler: file_handler)
    end

    # loads cfa model and ensure all collection keys have [] suffix
    def load
      super
      fix_collection_names(data)
    end

    # Adds pool entry to configuration.
    #
    # Strategy for placing new entry is:
    #
    #   1. If there is a already pool entry, place it afterwards.
    #   2. If there is common comment line above pool entries, place it afterwards.
    #   3. Append to end of file.
    #
    # @param address [String] pool address. Can be either hostname or ip address.
    # @param options [Symbol, Hash<String, nil | String>] can be either `:default` symbol of Hash.
    #   When `:default` is used, then default options is used. See {#default_pool_options}.
    #   When hash is used, then format is that key is option name and
    #   value is either nil for keyword options or String with value for key value options
    def add_pool(address, options = :default)
      options = default_pool_options if options == :default
      # if there is already pool entry, place it after, if not, try use comment
      existing_pools = pure_pools
      matcher = if existing_pools.empty?
        # for now first chrony have pools under comment mentioning pool.ntp.org
        # so try to place it below
        Matcher.new { |k, v| k.start_with?("#comment") && v =~ /www\.pool\.ntp\.org/ }
      else
        # place after the last pool available
        Matcher.new(key:           existing_pools.last[:key],
                    value_matcher: existing_pools.last[:value])
      end
      placer = AfterPlacer.new(matcher)

      key = "pool[]"
      value = AugeasTreeValue.new(AugeasTree.new, address)
      options.each_pair do |k, v|
        value.tree[k] = v
      end

      data.add(key, value, placer)
    end

    # modifies pool entry with original address to new adress and specified options
    # @param original_address [String] address to modify
    # @param new_address [String] new adress of pool entry. Can be same as original one
    # @param options [Hash<String, nil | String>] options format is that key is option name and
    #   value is either nil for keyword options or String with value for key value options
    def modify_pool(original_address, new_address, options)
      matcher = pool_matcher(original_address)
      value = AugeasTreeValue.new(AugeasTree.new, new_address)
      options.each_pair do |k, v|
        value.tree[k] = v
      end

      placer = AfterPlacer.new(matcher)

      key = "pool[]"
      data.delete(matcher)
      data.add(key, value, placer)
    end

    # deletes pool entry
    # @param address [String] pool to delete
    def delete_pool(address)
      matcher = pool_matcher(address)

      data.delete(matcher)
    end

    def default_pool_options
      { "iburst" => nil }
    end

    # delete all pools defined
    def clear_pools
      data.delete(POOLS_MATCHER)
    end

    # returns copy of available pools
    # TODO allow modify of specific pool
    # hash with key server and value is options hash
    def pools
      pools_data = pure_pools.map { |p| p[:value] }
      pools_map = pools_data.map do |entry|
        case entry
        when String
          [entry, {}]
        when AugeasTreeValue
          options = Hash[entry.tree.data.map { |e| [e[:key], e[:value]] }]
          [entry.value, options]
        else
          raise "invalid pool data #{entry.inspect}"
        end
      end

      Hash[pools_map]
    end

    # Is there any hardware clock settings?
    def hardware_clock?
      !data.select(Matcher.new(collection: "refclock")).empty?
    end

  private

    COLLECTION_KEYS = [
      "pool",
      "refclock"
    ].freeze
    # if there is only one element of collection, augeas does not add [],
    # so fix it here for known keys which we modify ( and can be hitted with it )
    def fix_collection_names(tree)
      tree.data.each do |entry|
        entry[:key] << "[]" if COLLECTION_KEYS.include?(entry[:key])
        fix_collection_names(entry[:value].tree) if entry[:value].is_a?(AugeasTreeValue)
        fix_collection_names(entry[:value]) if entry[:value].is_a?(AugeasTree)
      end
    end

    POOLS_MATCHER = Matcher.new(collection: "pool")

    # list of pools in internal data structure
    def pure_pools
      data.select(POOLS_MATCHER)
    end

    def pool_matcher(address)
      Matcher.new do |k, v|
        k == "pool[]" &&
          (v.respond_to?(:value) ? v.value == address : v == address)
      end
    end
  end
end
