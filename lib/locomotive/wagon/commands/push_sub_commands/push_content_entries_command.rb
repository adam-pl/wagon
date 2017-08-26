module Locomotive::Wagon

  class PushContentEntriesCommand < PushBaseCommand

    attr_reader :step

    alias_method :default_push, :_push

    def _push
      ([:without_relationships] + other_locales + [:only_relationships]).each do |step|
        @step = step
        default_push
      end
    end

    def entities
      content_types = repositories.content_type.all.to_a
      sorted_content_types = content_types.sort { |x,y| (r = -(x.display_settings['position'] <=> y.display_settings['position'])).zero? ? x.name <=> y.name : r }
      @entities ||= sorted_content_types.map do |content_type|
        # bypass a locale if there is no fields marked as localized
        next if locale? && content_type.fields.localized_names.blank?

        list = repositories.content_entry.with(content_type).all
        validate_entities(content_type, list)
      end.compact.flatten
    end

    def validate_entities(content_type, entities)
      instrument :validation, message: content_type.name

      #binding.pry

      # przygotuj liste definicji wymaganych pol
      required_fields = content_type.try(:entries_custom_fields).try(:adapter).collection.select { |x| x[:required] }
      # utworz tablice z nazwami wymaganych pol
      field_names = required_fields.map { |x| x[:name] }
      # iteruj po wszystkich rekordach i sprawdzaj czy wymagane pola nie sa puste
      entities.each do |entity|
        data = entity.to_hash
        required_fields.each do |required_field|
          field_name = required_field[:name]
          if ((data.has_key?(field_name) || data.has_key?(field_name + '_id')) && (!data[field_name].nil? || !data[field_name + '_id'].nil? ))
            ok = false
            case required_field[:type]
            when 'string', 'text'
              if data[field_name].respond_to? :strip
                ok = !data[field_name].strip.empty?
              elsif data[field_name].is_a? Locomotive::Steam::Models::I18nField
                ok = true
                data[field_name].to_hash.each do |translation|
                  if translation.nil? || translation.last.strip.empty?
                    ok = false
                    break
                  end
                end
              else
                puts "error: unknown class for 'string' field type"
              end
            when 'file'
              if !data[field_name].filename.nil? && !data[field_name].filename.empty?
                file_name = File.join( 'public', data[field_name].filename)
                ok = File.exists? file_name
                if !ok
                  puts "error: file_name doesn't exists: #{file_name}"
                end
              end
            when 'integer'
              ok = data[field_name].is_a? Fixnum
            when 'select'
              ok = !data[field_name + '_id'].strip.empty?
            when 'boolean'
              ok = (data[field_name] == true || data[field_name] == false)
            when 'date_time'
              ok = data[field_name].is_a? DateTime
            when 'date'
              ok = data[field_name].is_a? Date
            when 'float'
              ok = data[field_name].is_a? Float
            else
              # binding.pry
              # typ pola nieobsluzony
              puts "unknown field tye"
            end
            next if ok
          end
          instrument :persist_with_error, message: "required field '#{field_name}' is missed\n\nrequired_fields: #{required_field}\n\ndata: #{data}"
          raise SkipPersistingException.new
        end
      end
      entities
    end

    def decorate(entity)
      if locale?
        ContentEntryWithLocalizedAttributesDecorator.new(entity, @step, path, content_assets_pusher)
      elsif only_relationships?
        ContentEntryWithOnlyRelationshipsDecorator.new(entity, default_locale, path, content_assets_pusher)
      else
        ContentEntryDecorator.new(entity, default_locale, path, content_assets_pusher)
      end
    end

    def persist(decorated_entity)
      attributes = decorated_entity.to_hash

      raise SkipPersistingException.new if attributes.blank?

      _locale = locale? ? @step : nil

      remote_entity = api_client.content_entries(decorated_entity.content_type).update(decorated_entity._id, attributes, _locale)

      # Note: very important to use the real id in the next API calls
      # because the _slug can be localized and so, won't be unique for
      # a content entry.
      decorated_entity._id = remote_entity._id
    end

    def label_for(decorated_entity)
      label = decorated_entity.__with_locale__(default_locale) { decorated_entity._label }
      label = "#{decorated_entity.content_type.name} / #{label}"

      if without_relationships?
        label
      elsif only_relationships?
        "#{label} with relationships"
      elsif locale?
        "#{label} in #{self.step}"
      end
    end

    private

    def other_locales
      return [] if current_site.locales.blank?
      current_site.locales - [current_site.default_locale]
    end

    def without_relationships?
      self.step == :without_relationships
    end

    def only_relationships?
      self.step == :only_relationships
    end

    def locale?
      other_locales.include?(self.step)
    end

  end

end

