require 'locomotive/coal'

module Locomotive::Wagon

  module ApiConcern

    # Instance of the API client to request an account or his/her list of sites.
    def api_client
      @api_client ||= Locomotive::Coal::Client.new(api_uri, api_credentials)
    end

    # Instance of the API client to request resources of a site: pages, theme_assets, ...etc.
    def api_site_client(site)
      @api_site_client = api_client.scope_by(site)
    end

    # Host (+ port) extracted from the platform_url instance variable.
    # If port equals 80, do not add it to the host.
    #
    # Examples:
    #
    #     www.myengine.com
    #     localhost:3000
    #
    def api_host
      uri = api_uri
      host, port = uri.host, uri.port

      port == 80 ? uri.host : "#{uri.host}:#{uri.port}"
    end

    def api_credentials
      if respond_to?(:email)
        { email: email, password: password }
      elsif respond_to?(:credentials)
        credentials
      end
    end

    private

    def api_uri
      if (self.platform_url =~ /^https?:\/\//).nil?
        self.platform_url = 'http://' + self.platform_url
      end

      URI(platform_url)
    end

  end

end