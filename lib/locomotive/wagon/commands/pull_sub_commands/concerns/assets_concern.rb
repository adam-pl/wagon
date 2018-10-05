require 'tempfile'

require_relative '../../../tools/yaml_ext.rb'

module Locomotive::Wagon

  module AssetsConcern

    REGEX = /(https?:\/\/\S+)?\/sites\/[0-9a-f]{24}\/(assets|pages|theme|content_entry[0-9a-f]{24})\/(([^;.]+)\/)*([a-zA-Z_\-0-9.%]+)(\?\w+)?/

    # The content assets on the remote engine follows the format: /sites/<id>/assets/<type>/<file>
    # This method replaces these urls by their local representation. <type>/<file>
    #
    # @param [ String ] content The text where the assets will be replaced.
    #
    def replace_asset_urls(content)
      return '' if content.blank?

      content.force_encoding('utf-8').gsub(REGEX) do |url|
        filename = $5
        folder = case $2
        when 'assets', 'pages'  then File.join('samples', $2)
        when 'theme'            then $4
        when /\Acontent_entry/  then File.join('samples', 'content_entries')
        end

        if filepath = write_asset(url, File.join(path, 'public', folder, filename))
          File.join('', folder, File.basename(filepath)).to_s
        else
          ''
        end
      end
    end

    def replace_asset_urls_in_hash(hash)
      Locomotive::Wagon::YamlExt.transform(hash) do |value|
        replace_asset_urls(value)
      end
    end

    private

    def find_unique_filepath(startfilepath, binary_file, index = 1)
      filepath = startfilepath

      while File.exists?(filepath)
        # required because we need to make sure we use the content of file from its start
        binary_file.rewind

        # return the same name if existed file has the same content
        return filepath if FileUtils.compare_stream(binary_file, File.open(filepath))

        folder, ext = File.dirname(startfilepath), File.extname(startfilepath)
        basename = File.basename(startfilepath, ext)
    
        prevfilepath = filepath
        # set new file path with adding index i.e. "1-1.jpg"; if exists check for: "1-2.jpg", "1-3.jpg"..., "1-10.jpg" etc
        filepath = File.join(folder, "#{basename}-%.5d#{ext}" % index)

        puts "Info => file '#{prevfilepath}' exists. Trying change it to '#{filepath}'"
        
        index += 1
      end

      filepath
    end

    def get_asset_binary(url)
      unless url =~ /\Ahttp:\/\//
        base = api_client.uri.dup.tap { |u| u.path = '' }.to_s
        url = URI.join(base, url).to_s
      end

      binary = Faraday.get(url).body rescue nil
    end

    def write_asset(url, filepath)
      if binary = get_asset_binary(url)
        FileUtils.mkdir_p(File.dirname(filepath))

        (binary_file = Tempfile.new(File.basename(filepath))).write(binary)

        find_unique_filepath(filepath, binary_file).tap do |filepath|
          File.open(filepath, 'wb') { |f| f.write(binary) }
        end
      else
        instrument :missing_asset, url: url
        nil
      end
    end

  end

end
