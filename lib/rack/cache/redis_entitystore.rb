require 'rack/cache/entitystore'

module Rack
  module Cache
    class EntityStore
      class RedisBase < self
        # The underlying ::Redis instance used to communicate with the Redis daemon.
        attr_reader :cache

        extend Rack::Utils

        def open(key)
          data = read(key)
          data && [data]
        end

        def self.resolve(uri)
          new OptionsExtractor.build_options(uri.to_s)
        end
      end

      class Redis < RedisBase
        def initialize(options = {})
          @cache = ::Readthis::Cache.new(options)
        end

        def exist?(key)
          cache.exist? key
        end

        def read(key)
          cache.read(key)
        end

        def write(body, ttl = 0)
          buf = StringIO.new
          key, size = slurp(body) { |part| buf.write(part) }

          if ttl.zero?
            [key, size] if cache.write(key, buf.string)
          else
            [key, size] if cache.write(key, buf.string, expires_in: ttl)
          end
        end

        def purge(key)
          cache.delete(key)
          nil
        end
      end

      REDIS = Redis
    end
  end
end
