class OptionsExtractor
  def self.build_options(url)
    uri = URI.parse(url)
    namespace = uri.path.split('/')[-1] if uri.path

    options = {}

    options[:redis] = { url: uri, driver: ENV.fetch('READTHIS_DRIVER', :ruby).to_sym }
    options[:expires_in] = ENV.fetch('RRC_EXPIRES_IN', 300).to_i
    options[:namespace] = namespace || 'cache'

    options
  end
end
