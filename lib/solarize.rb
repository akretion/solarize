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
        Sunspot::Adapters::DataAccessor.register(DataAccessor, base)
        Sunspot::Adapters::InstanceAdapter.register(InstanceAdapter, base)
      end
    end

    module ActsAsMethods
      def searchable?; true; end

      def auto_setup()
        unless Setup.for(self)
          Sunspot.setup(self) do #TODO use introspection + DSL to set some default search behavior
          end
        end
      end

      def solr_search(options = {}, &block)
        auto_setup() #that won't destroy any pre-existing manual setup
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
        hits.map do |hit|
          p "SSSSSSSSSS", hit.stored_value
        end
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
        super
        Sunspot.config.solr.url = Ooor.default_config[:solr_url]
      end
    end
  end
  
  module SolrLoader
    extend ActiveSupport::Concern
              
    SCHEMA_SUFFIXES = /_ss$|_texts$|_is$|_ds$|_dts$|_bins$|_fs$|_bs$|_sms$/
    module ClassMethods
      def from_solr(stored_values)
        fields = {}
        stored_values.each do |k, v| #TODO relations
          #process_m2o(fields, k)
          fields[k.sub(SCHEMA_SUFFIXES, '')] = v #TODO not if m2o
        end
        fields.merge!({solr_id: stored_values['id'], solr_score: stored_values['score'], id: stored_values['id'].split(' ')[2]})
        new(fields, [])
      end
    end
  end
  
  Ooor::Base.send :include, Ooor::SolrLoader

  include Ooor::SunspotConfigurator
end
