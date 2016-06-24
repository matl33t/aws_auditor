require_relative './instance_helper'

module AwsAuditor
  class CacheInstance
    extend InstanceHelper
    extend CacheWrapper
    extend AWSWrapper

    class << self
      attr_accessor :instances, :reserved_instances
    end

    attr_accessor :id, :name, :instance_type, :engine, :count, :tag_value
    def initialize(cache_instance, reserved, account_id=nil, tag_name=nil, cache=nil)
      if reserved
        self.id = cache_instance.reserved_cache_node_id
        self.name = cache_instance.reserved_cache_node_id
        self.instance_type = cache_instance.cache_node_type
        self.engine = cache_instance.product_description
        self.count = cache_instance.cache_node_count
      else
        self.id = cache_instance.cache_cluster_id
        self.name = cache_instance.cache_cluster_id
        self.instance_type = cache_instance.cache_node_type
        self.engine = cache_instance.engine
        self.count = cache_instance.num_cache_nodes

        if tag_name
          region = cache_instance.preferred_availability_zone.split(//).first(9).join
          region = "us-east-1" if region == "Multiple"
          arn = "arn:aws:elasticache:#{region}:#{account_id}:cluster:#{self.id}"

          cache.list_tags_for_resource(resource_name: arn).tag_list.each do |tag| # go through to see if the tag we're looking for is one of them
            if tag.key == tag_name
              self.tag_value = tag.value
            end
          end
        end
      end
    end

    def to_s
      "#{engine} #{instance_type}"
    end

    def self.get_instances(tag_name=nil)
      return @instances if @instances
      account_id = get_account_id
      @instances = cache.describe_cache_clusters.cache_clusters.map do |instance|
        next unless instance.cache_cluster_status.to_s == 'available'
        new(instance, false, account_id, tag_name, cache)
      end.compact
    end

    def no_reserved_instance_tag_value
      @tag_value
    end

    def self.get_reserved_instances
      return @reserved_instances if @reserved_instances
      @reserved_instances = cache.describe_reserved_cache_nodes.reserved_cache_nodes.map do |instance|
        next unless instance.state.to_s == 'active'
        new(instance, true)
      end.compact
    end
    
  end
end
