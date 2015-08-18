require 'test_helper'

describe Rack::Cache::MetaStore::Redis do
  before do
    @store        = ::Rack::Cache::MetaStore::Redis.resolve('redis://127.0.0.1')
    @entity_store = ::Rack::Cache::EntityStore::Redis.resolve('redis://127.0.0.1:6380')
    @request  = mock_request('/', {})
    @response = mock_response(200, {}, ['hello world'])
  end

  after do
    @store.cache.clear
    @entity_store.cache.clear
  end

  it "has the class referenced by homonym constant" do
    ::Rack::Cache::MetaStore::REDIS.must_equal(::Rack::Cache::MetaStore::Redis)
  end

  it "instantiates the store" do
    @store.must_be_kind_of(::Rack::Cache::MetaStore::Redis)
  end

  it "resolves the connection uri" do
    cache = Rack::Cache::MetaStore::Redis.resolve('redis://127.0.0.1').cache
    cache.must_be_kind_of(::Readthis::Cache)

    cache = Rack::Cache::MetaStore::Redis.
      resolve('redis://127.0.0.1:6380/0/metastore').cache
    cache.options[:namespace].must_equal('metastore')
  end

  it 'sets expires_in to the value of the ENV var when set' do
    ENV['RRC_EXPIRES_IN'] = '60'
    cache = Rack::Cache::MetaStore::Redis.
            resolve('redis://127.0.0.1:6380/0/metastore').cache

    cache.options[:expires_in].must_equal(60)
    ENV['RRC_EXPIRES_IN'] = nil
  end

  it 'defaults expires_in to 300 when ENV var is not set' do
    cache = Rack::Cache::MetaStore::Redis.
            resolve('redis://127.0.0.1:6380/0/metastore').cache

    cache.options[:expires_in].must_equal(300)
  end

  it 'sets driver to the value of the ENV var when set' do
    ENV['READTHIS_DRIVER'] = 'hiredis'
    cache = Rack::Cache::MetaStore::Redis.
            resolve('redis://127.0.0.1:6380/0/metastore').cache

    cache.pool.with do |client|
      client.client.driver.must_equal(Redis::Connection::Hiredis)
    end

    ENV['READTHIS_DRIVER'] = nil
  end

  it 'defaults to ruby driver when ENV var is not set' do
    cache = Rack::Cache::MetaStore::Redis.
            resolve('redis://127.0.0.1:6380/0/metastore').cache

    cache.pool.with do |client|
      client.client.driver.must_equal(Redis::Connection::Ruby)
    end
  end

  # Low-level implementation methods ===========================================

  it 'writes a list of negotation tuples with #write' do
    # lambda {
      @store.write('/test', [[{}, {}]])
    # }.wont_raise Exception
  end

  it 'reads a list of negotation tuples with #read' do
    @store.write('/test', [[{},{}],[{},{}]])
    tuples = @store.read('/test')
    tuples.must_equal([ [{},{}], [{},{}] ])
  end

  it 'reads an empty list with #read when nothing cached at key' do
    @store.read('/nothing').must_be_empty
  end

  it 'removes entries for key with #purge' do
    @store.write('/test', [[{},{}]])
    @store.read('/test').wont_be_empty

    @store.purge('/test')
    @store.read('/test').must_be_empty
  end

  it 'succeeds when purging non-existing entries' do
    @store.read('/test').must_be_empty
    @store.purge('/test')
  end

  it 'returns nil from #purge' do
    @store.write('/test', [[{},{}]])
    @store.purge('/test').must_be_nil
    @store.read('/test').must_equal([])
  end

  %w[/test http://example.com:8080/ /test?x=y /test?x=y&p=q].each do |key|
    it "can read and write key: '#{key}'" do
      # lambda {
        @store.write(key, [[{},{}]])
      # }.wont_raise Exception
      @store.read(key).must_equal([[{},{}]])
    end
  end

  it "can read and write fairly large keys" do
    key = "b" * 4096
    # lambda {
      @store.write(key, [[{},{}]])
    # }.wont_raise Exception
    @store.read(key).must_equal([[{},{}]])
  end

  it "allows custom cache keys from block" do
    request = mock_request('/test', {})
    request.env['rack-cache.cache_key'] =
      lambda { |request| request.path_info.reverse }
    @store.cache_key(request).must_equal('tset/')
  end

  it "allows custom cache keys from class" do
    request = mock_request('/test', {})
    request.env['rack-cache.cache_key'] = Class.new do
      def self.call(request); request.path_info.reverse end
    end
    @store.cache_key(request).must_equal('tset/')
  end

  it 'does not blow up when given a non-marhsalable object with an ALL_CAPS key' do
    store_simple_entry('/bad', { 'SOME_THING' => Proc.new {} })
  end

  # Abstract methods ===========================================================

  it 'stores a cache entry' do
    cache_key = store_simple_entry
    @store.read(cache_key).wont_be_empty
  end

  it 'sets the X-Content-Digest response header before storing' do
    cache_key = store_simple_entry
    req, res = @store.read(cache_key).first
    res['X-Content-Digest'].must_equal('a94a8fe5ccb19ba61c4c0873d391e987982fbbd3')
  end

  it 'finds a stored entry with #lookup' do
    store_simple_entry
    response = @store.lookup(@request, @entity_store)
    response.wont_be_nil
    response.must_be_kind_of(Rack::Cache::Response)
  end

  it 'does not find an entry with #lookup when none exists' do
    req = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
    @store.lookup(req, @entity_store).must_be_nil
  end

  it "canonizes urls for cache keys" do
    store_simple_entry(path='/test?x=y&p=q')

    hits_req = mock_request(path, {})
    miss_req = mock_request('/test?p=x', {})

    @store.lookup(hits_req, @entity_store).wont_be_nil
    @store.lookup(miss_req, @entity_store).must_be_nil
  end

  it 'does not find an entry with #lookup when the body does not exist' do
    store_simple_entry
    @response.headers['X-Content-Digest'].wont_be_nil
    @entity_store.purge(@response.headers['X-Content-Digest'])
    @store.lookup(@request, @entity_store).must_be_nil
  end

  it 'restores response headers properly with #lookup' do
    store_simple_entry
    response = @store.lookup(@request, @entity_store)
    response.headers.
      must_equal(@response.headers.merge('Content-Length' => '4'))
  end

  it 'restores response body from entity store with #lookup' do
    store_simple_entry
    response = @store.lookup(@request, @entity_store)
    body = '' ; response.body.each {|p| body << p}
    body.must_equal('test')
  end

  it 'invalidates meta and entity store entries with #invalidate' do
    store_simple_entry
    @store.invalidate(@request, @entity_store)
    response = @store.lookup(@request, @entity_store)
    response.must_be_kind_of(Rack::Cache::Response)
    response.wont_be :fresh?
  end

  it 'succeeds quietly when #invalidate called with no matching entries' do
    req = mock_request('/test', {})
    @store.invalidate(req, @entity_store)
    @store.lookup(@request, @entity_store).must_be_nil
  end

  # Vary =======================================================================

  it 'does not return entries that Vary with #lookup' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo', 'HTTP_BAR' => 'Bar'})
    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res = mock_response(200, {'Vary' => 'Foo Bar'}, ['test'])
    @store.store(req1, res, @entity_store)

    @store.lookup(req2, @entity_store).must_be_nil
  end

  it 'stores multiple responses for each Vary combination' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
    key = @store.store(req1, res1, @entity_store)

    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
    @store.store(req2, res2, @entity_store)

    req3 = mock_request('/test', {'HTTP_FOO' => 'Baz',   'HTTP_BAR' => 'Boom'})
    res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
    @store.store(req3, res3, @entity_store)

    slurp(@store.lookup(req3, @entity_store).body).must_equal('test 3')
    slurp(@store.lookup(req1, @entity_store).body).must_equal('test 1')
    slurp(@store.lookup(req2, @entity_store).body).must_equal('test 2')

    @store.read(key).length.must_equal(3)
  end

  it 'overwrites non-varying responses with #store' do
    req1 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res1 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 1'])
    key = @store.store(req1, res1, @entity_store)
    slurp(@store.lookup(req1, @entity_store).body).must_equal('test 1')

    req2 = mock_request('/test', {'HTTP_FOO' => 'Bling', 'HTTP_BAR' => 'Bam'})
    res2 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 2'])
    @store.store(req2, res2, @entity_store)
    slurp(@store.lookup(req2, @entity_store).body).must_equal('test 2')

    req3 = mock_request('/test', {'HTTP_FOO' => 'Foo',   'HTTP_BAR' => 'Bar'})
    res3 = mock_response(200, {'Vary' => 'Foo Bar'}, ['test 3'])
    @store.store(req3, res3, @entity_store)
    slurp(@store.lookup(req1, @entity_store).body).must_equal('test 3')

    @store.read(key).length.must_equal(2)
  end

  private

  define_method :mock_request do |uri, opts|
    env = Rack::MockRequest.env_for(uri, opts || {})
    Rack::Cache::Request.new(env)
  end

  define_method :mock_response do |status, headers, body|
    headers ||= {}
    body = Array(body).compact
    Rack::Cache::Response.new(status, headers, body)
  end

  define_method :slurp do |body|
    buf = ''
    body.each { |part| buf << part }
    buf
  end

  # Stores an entry for the given request args, returns a url encoded cache key
  # for the request.
  define_method :store_simple_entry do |*request_args|
    path, headers = request_args
    @request = mock_request(path || '/test', headers || {})
    @response = mock_response(200, {'Cache-Control' => 'max-age=420'}, ['test'])
    body = @response.body
    cache_key = @store.store(@request, @response, @entity_store)
    @response.body.must_equal(body)
    cache_key
  end
end
