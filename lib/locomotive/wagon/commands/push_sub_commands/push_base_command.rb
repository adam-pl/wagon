module Locomotive::Wagon

  class PushBaseCommand < Struct.new(:api_client, :steam_services, :content_assets_pusher, :remote_site, :filter)

    extend Forwardable

    def_delegators :steam_services, :current_site, :locale, :repositories

    THREADS_COUNT = 15

    def self.push(api_client, steam_services, content_assets_pusher, remote_site)
      instance = new(api_client, steam_services, content_assets_pusher, remote_site)
      yield instance if block_given?
      instance.push
    end

    def push
      instrument do
        instrument :start
        self._push_with_timezone
        instrument :done
      end
    end

    def _push_with_timezone
      Time.use_zone(current_site.try(:timezone)) do
        _push
      end
    end

    def _push
      entities.each do |entity|
        push_entity( entity)
      end
    end

    def _push_multithread
      error = false
      return if entities.empty?
      puts "TOTAL ENTITIES: #{entities.size}"
      threads = []
      entities.each_slice(entities.size / THREADS_COUNT + 1).to_a.each do |entities2|
        threads << Thread.new {
          #Time.zone = 'Warsaw'          # Bardzo wazne, bo w kazdym nowym watku Time.zone jest nilem!
          Time.zone = current_site.try(:timezone)
          puts "Time.zone: #{Time.zone}"
          entities2.each do |entity|
            if error
              instrument :warning, message: 'thread task execution interrupted'
              break
            end
            push_entity( entity)
          end
        }
      end

      threads.each do |thread|
        thread.join
      end

      if error
        instrument :error, message: 'process interrupted'
        raise Exception.new
      end
    end

    def push_entity(entity)
      decorated = decorate(entity)
      begin
        instrument :persist, label: label_for(decorated)
        persist(decorated)
        instrument :persist_with_success
      rescue SkipPersistingException => e
        instrument :skip_persisting
      rescue Locomotive::Coal::ServerSideError => e
        instrument :persist_with_error, message: 'Locomotive Back-office error. Contact your administrator or check your application logs.'
        raise e
      rescue Exception => e
        instrument :persist_with_error, message: e.message
        raise e
      end
    end

    def instrument(action = nil, payload = {}, &block)
      name = ['wagon.push', [*action]].flatten.compact.join('.')
      ActiveSupport::Notifications.instrument(name, { name: resource_name }.merge(payload), &block)
    end

    def resource_name
      self.class.name[/::Push(\w+)Command$/, 1].underscore
    end

    def default_locale
      current_site.default_locale
    end

    def locales
      current_site.locales
    end

    def path
      File.expand_path(repositories.adapter.options[:path])
    end

    def with_data
      @with_data = true
    end

    def with_data?
      !!@with_data
    end

    def only(entities)
      @only_entities = entities.map do |entity_or_filter|
        Locomotive::Wagon::Glob.new(entity_or_filter.gsub(/\A\//, '')).to_regexp
      end
    end

    class SkipPersistingException < Exception
    end

  end

end
