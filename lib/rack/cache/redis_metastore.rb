require 'digest/sha1'
require 'rack/utils'
require 'rack/cache/key'
require 'rack/cache/metastore'

module Rack
  module Cache
    class MetaStore
      class RedisBase < self
        extend Rack::Utils

        # The Redis::Store object used to communicate with the Redis daemon.
        attr_reader :cache

        def self.resolve(uri)
          new OptionsExtractor.build_options(uri.to_s)
        end
      end

      class Redis < RedisBase
        # The Redis instance used to communicate with the Redis daemon.
        attr_reader :cache

        def initialize(options = {})
          @cache = ::Readthis::Cache.new(options)
        end

        def read(key)
          cache.read(hexdigest(key)) || []
        end

        def write(key, value, options = {})
          cache.write(hexdigest(key), value, options)
        end

        def purge(key)
          cache.delete(hexdigest(key))
          nil
        end
      end

      REDIS = Redis
    end
  end
end
