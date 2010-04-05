require 'ripple'

module Ripple
  module Document
    module Indexing
      extend ActiveSupport::Concern

      included do
        after_save :index_attributes
      end

      module ClassMethods
        def attribute_indexed?(attribute)
          !attribute.nil? && indexed_attributes.include?(attribute)
        end

        def indexed_attributes
          @indexed_attributes ||= []
        end

        def index(attribute)
          indexed_attributes << attribute
        end

        def property(key, type, options={})
          prop = super
          index(prop.key) if options[:index]
          prop
        end

        def index_bucket_name(attribute)
          "#{bucket_name}_by_#{attribute}"
        end

        def index_bucket(attribute)
          Ripple.client[index_bucket_name(attribute)]
        end

        def index_robject(attribute, value)
          index_bucket(attribute)[value.hash.to_s] unless value.blank?
        rescue Riak::FailedRequest
          nil
        end

        def robjects_by_indexed_attribute(attribute, value)
          robject = index_robject(attribute, value)
          robject.nil? ? [] : robject.walk(:bucket => bucket_name, :keep => true).first
        end
      end

      module InstanceMethods
        def link_to_index(attribute)
          index_bucket_name = self.class.index_bucket_name(attribute)
          robject_links.find do |link|
            link.bucket == index_bucket_name
          end
        end

        def index_attributes
          self.class.indexed_attributes.each do |attribute|
            Index.refresh(self, attribute)
          end
        end

        def robject_store
          robject.store
        end

        def robject_links
          robject.links
        end

        def robject_to_link(rel)
          robject.to_link(rel)
        end
      end
    end

    class Index
      attr_reader :document, :attribute
      attr_writer :index_robject

      def self.find(document, attribute)
        new(document, attribute)
      end

      def self.refresh(document, attribute)
        find(document, attribute).refresh
      end

      def initialize(document, attribute)
        @document = document
        @attribute = attribute
      end

      def link_to_document
        @link_to_document ||= index_robject_links.find { |link| link.key == document.key }
      end

      def link_to_document?
        !link_to_document.nil?
      end

      def link_to_index
        @link_to_index ||= document.link_to_index(attribute)
      end

      def link_to_index?
        !link_to_index.nil?
      end

      def index_bucket
        document.class.index_bucket(attribute)
      end

      def index_robject
        @index_robject ||= (index_bucket[link_to_index.key] if link_to_index?)
      end

      def index_robject?
        !index_robject.nil?
      end

      def attribute_value
        document.attributes[attribute]
      end

      def hashed_attribute_value
        attribute_value.hash.to_s
      end

      def attribute_value_changed?
        CGI.unescape(link_to_index.key) != hashed_attribute_value
      end

      def linked?
        link_to_index? && link_to_document?
      end

      def stale?
        !linked? || attribute_value_changed?
      end

      def refresh
        if stale?
          delete
          store
          refresh_index_robject
          link
          store
        end
      end

      def delete
        index_robject_links.delete(link_to_document) if index_robject?
        document_robject_links.delete(link_to_index)
      end

      def document_robject_links
        document.robject_links
      end

      def index_robject_links
        index_robject.links
      end

      def refresh_index_robject
        @index_robject = index_bucket.get_or_new(hashed_attribute_value)
      end

      def link
        index_robject_links << document_robject_to_link
        document_robject_links << index_robject_to_link
      end

      def document_robject_to_link
        document.robject_to_link(relation)
      end

      def index_robject_to_link
        index_robject.to_link(relation)
      end

      def store
        index_robject.store if index_robject?
        document.robject_store
      end

      def relation
        "#{document_bucket_name}_by_#{attribute}_index"
      end

      def document_bucket_name
        document.class.bucket_name
      end
    end
  end
end