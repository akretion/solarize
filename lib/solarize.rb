require 'active_support/concern'
require 'sunspot'
require 'ooor'


module Sunspot
  module Ooor
    
    def self.backend_to_connection_spec()
      #TODO use some ooor.yml config to match a backend with a connection
    end

    def self.included(base)
      base.class_eval do
        extend Sunspot::Ooor::ActsAsMethods
        extend MakeItSearchable
        Sunspot::Adapters::DataAccessor.register(DataAccessor, base)
        Sunspot::Adapters::InstanceAdapter.register(InstanceAdapter, base)
      end
    end


    module MakeItSearchable
      OE2SOLR = {
                  'selection' => ['string', 's'],
                  'char' => ['string', 's'],
                  'text' => ['text', 'text'],
                  'boolean' => ['boolean', 'b'],
                  'integer' => ['integer', 'i'],
                  'float' => ['float', 'f'],
                  'date' => ['date', 'd'],
                  'datetime' => ['datetime', 'dt']
                }
      def make_it_searchable
        #TODO don't do that twice
        searchable(auto_index: false, auto_remove: false) do
          string 'id', as: 'id'
          text 'text' #default text search. use may use copyField to fill it.
          fields.each do |k, v|
            if t = OE2SOLR[v['type']]
              options = {stored: true, as: "#{k}_#{t[1]}s"}
              send t[0], k, options
            end
          end

          many2one_associations.each do |k, v|
            options = {stored: true, as: "#{k}/id_is"} #TODO name
            integer k, options
          end
          #TODO included many2one. introspection method in solerp?

          one2many_associations.each do |k, v|
            options = {stored: true, multiple: true, as: "#{k}/id_ims"} #TODO names
            integer k, options
          end

          many2many_associations.each do |k, v|
            options = {stored: true, multiple: true, as: "#{k}/id_ims"} #TODO names
            integer k, options
          end

        end
      end
    end


    module ActsAsMethods
      def searchable?; true; end

      def searchable(options = {}, &block)
        unless @searchable
          Sunspot.setup(self, &block)
          class_attribute :sunspot_options
          @searchable = true
        end
        options[:include] = Util::Array(options[:include])
        self.sunspot_options = options
      end

      def solr_search(options = {}, &block)
        unless @searchable
          reload_fields_definition()
          make_it_searchable()
        end
        conn = self.connection
        solr_execute_search(options) do
          Sunspot.new_search(self, &block).tap do |search|
            search.ooor_session = conn
            def search.results #TODO strangely this doesn't seem to work anymore!!
              @results ||= paginate_collection(verified_hits(self.ooor_session).map do |hit|
                hit.ooor_results(self.ooor_session) #TODO actually pass only the spec
              end)
            end
            
            def search.verified_hits(session)
              hits.select { |h| h.ooor_results(session) }
            end
          end
        end
      end

      def solr_search_ids(&block)
        solr_execute_search_ids do
          solr_search(&block)
        end
      end

      def solr_execute_search(options = {})
        options.assert_valid_keys(:include, :select)
        search = yield
        unless options.empty?
          search.build do |query|
            if options[:include]
              query.data_accessor_for(self).include = options[:include]
            end
            if options[:select]
              query.data_accessor_for(self).select = options[:select]
            end
          end
        end
        search.execute
      end

      def solr_execute_search_ids(options = {})
        search = yield
        search.raw_results.map { |raw_result| raw_result.primary_key.to_i }
      end

      def solr_more_like_this(*args, &block)
        options = args.extract_options!
        self.class.solr_execute_search(options) do
          Sunspot.new_more_like_this(self, *args, &block)
        end
      end

      def solr_more_like_this_ids(&block)
        self.class.solr_execute_search_ids do
          solr_more_like_this(&block)
        end
      end

    end


    module Search
      class OoorHit < Sunspot::Search::Hit
        attr_reader :backend, :stored_values

        def initialize(raw_hit, highlights, search) #:nodoc:
          t = raw_hit['id'].split(' ')
          @class_name = t[1]#.gsub('-', '_').camelize
          @primary_key = t[2]
          @backend = t[0]
          @score = raw_hit['score']
          @search = search
          @stored_values = raw_hit
          @stored_cache = {}
          @highlights = highlights
        end
        
        def ooor_results(session) #TODO use connection spec instead (hits from several connections)
          return @result if defined?(@result)
          @search.populate_hits(session)
          @result
        end

      end

      module OoorHitEnumerable
        attr_accessor :ooor_session # TODO only session spec

        def hits(options = {})
          if options[:verify]
            verified_hits
          elsif solr_docs
            solr_docs.map { |d| OoorHit.new(d, highlights_for(d), self) }
          else
            []
          end
        end

        # 
        # Populate the Hit objects with their instances. This is invoked the first
        # time any hit has its instance requested, and all hits are loaded as a
        # batch.
        #
        def populate_hits(session)
          id_hit_hash = Hash.new { |h, k| h[k] = {} }
          hits.each do |hit|
            id_hit_hash[hit.class_name][hit.primary_key] = hit
          end
          id_hit_hash.each_pair do |class_name, hits|
            hits_for_class = id_hit_hash[class_name]
            hits.each do |hit_pair|
              hit_pair[1].result = session[class_name].from_solr(hit_pair[1].stored_values)
            end
          end
        end

      end
    end


    class InstanceAdapter < Sunspot::Adapters::InstanceAdapter
      def id
        @instance.id # NOTE sure?
      end
    end

    # NOTE useless as it is because not multi-session?
    class DataAccessor < Sunspot::Adapters::DataAccessor
      def load(id)
        @clazz.find(id)
      end

      def load_all(ids)
        @clazz.find(ids)
      end

      def load_all_from_solr(hits)
        hits.map { |hit| hit.stored_value }
      end

    end
  end
end

Ooor::Base.send :include, Sunspot::Ooor

Sunspot::Search::AbstractSearch.send :include, Sunspot::Ooor::Search::OoorHitEnumerable


module Ooor
  module SunspotConfigurator
    extend ActiveSupport::Concern
    module ClassMethods
      def new(config={})
        res = super
        Sunspot.config.solr.url = Ooor.default_config[:solr_url]
        res
      end
    end
  end
  
  module SolrLoader
    extend ActiveSupport::Concern
              
    SCHEMA_SUFFIXES = /_ss$|_texts$|_is$|_its$|_ds$|_dts$|_bins$|_fs$|_bs$|_sms$|_itms$|_ims$/
    module ClassMethods
      def from_solr(stored_values, consumed_keys=[])
        reload_fields_definition
        fields = {}
        level0_m2o_keys = many2one_associations.merge(polymorphic_m2o_associations)
        level0_m2o_keys.each do |m2o_key, m2o|
          consumed_keys << m2o_key
          model_key = m2o['relation']
          related_class = self.const_get(model_key)
          m2o_hash = {}
          stored_values.each do |k, v|
            if k =~ /^#{m2o_key}\//
              consumed_keys << k
              m2o_hash[k.sub(/^#{m2o_key}\//, '')] = v
            end
          end
          unless m2o_hash.keys.empty?
            fields[m2o_key] = related_class.from_solr(m2o_hash)
          end
        end

        associations = one2many_associations.merge(many2many_associations)
        (stored_values.keys - consumed_keys).each do |k|
#          if m = /-(o|m)2m(-m2o|)_sms$/.match(k)
          if k.end_with?('_sms')
#            x2m_key = k.sub(/-(o|m)2m(-m2o|)_sms$/, '').split('-')[0]
            x2m_key = k.split("/")[0]
            x2m = associations[x2m_key]
            model_key = x2m['relation']
            related_class = self.const_get(model_key)
            ids = stored_values["#{x2m_key}/id_ims"]
            name = k.split('/')[1].sub('_sms', '')
            fields[x2m_key] = []
            consumed_keys << k
            consumed_keys << "#{x2m_key}/id_ims"
            if k.split('/').size > 2 #item decription is carried by a m2o
              vals = stored_values[k]
              m2o_key = k.split('/')[1]
              m2o_ids = stored_values["#{x2m_key}/#{m2o_key}/id_ims"]
              ids.each_with_index do |id, index|
                x2m_hash = {"id" => id}
                rec_name = k.split('/')[2].sub('_sms', '')
                related_class.reload_fields_definition
                if m2o = related_class.many2one_associations[name]
                  m2o_class = self.const_get(m2o['relation'])
                  x2m_hash[name] = m2o_class.new({"id" => m2o_ids[index], rec_name => vals[index]}, [])
                end
                fields[x2m_key] << related_class.new(x2m_hash, [])
              end
            else # flat item description
              vals = stored_values[k]
              ids.each_with_index do |id, index|
                x2m_hash = {"id" => id, name => vals[index]}
                fields[x2m_key] << related_class.new(x2m_hash, [])
              end
            end
          end
        end

        (stored_values.keys - consumed_keys).each do |k|
          fields[k.sub(SCHEMA_SUFFIXES, '')] = stored_values[k]
        end
        if stored_values['id'].is_a?(String)
          id = stored_values['id'].split(' ')[2]
          fields.merge!({solr_id: stored_values['id'], solr_score: stored_values['score'], id: id})
        end
        new(fields, [])
      end
    end
  end
  
  Ooor::Base.send :include, Ooor::SolrLoader

  include Ooor::SunspotConfigurator
end
