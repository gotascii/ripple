require 'ripple'

#   class Email
#     include Ripple::Document
#     property :from,    String, :presence => true
#     index :from
#   end

module Ripple
  module Document
    module Indexing
      extend ActiveSupport::Concern

      included do
        after_save :index_attributes
      end

      module InstanceMethods
        ###
        def link_to_index(attribute)
          robject.links.find { |link| link.bucket == index_bucket_name(attribute) }
        end

        def index_bucket_name(attribute)
          "#{self.class.plural_name}_by_#{attribute}"
        end

        ###
        def index_attributes
          model.indexed_attributes.each do |attribute|
            Index.find(self, attribute).refresh
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

      module ClassMethods
        def indexed_attributes
          @indexed_attributes ||= []
        end

        def index(attribute)
          indexed_attributes << attribute
        end

        def plural_name
          name.pluralize.downcase
        end
      end
    end

    class Index
      attr_reader :document, :attribute

      def self.find(document, attribute)
        new(document, attribute)
      end

      def initialize(document, attribute)
        @document = document
        @attribute = attribute
      end

      ###
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
        Ripple.client[link_to_index.bucket]
      end

      def index_robject
        index_bucket[link_to_index.key]
      end

      def attribute_value
        document.attributes[attribute]
      end

      def attribute_value_changed?
        CGI.unescape(link_to_index.key) != attribute_value
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
          link
          store
        end
      end

      def delete
        index_robject_links.delete(link_to_document)
        document_robject_links.delete(link_to_index)
      end

      def document_robject_links
        document.robject_links
      end

      def index_robject_links
        index_robject.links
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
        index_robject.store
        document.robject_store
      end

      def relation
        "#{plural_model_name}_by_#{attribute}_index"
      end

      def plural_model_name
        document.class.plural_name
      end
    end
  end
end