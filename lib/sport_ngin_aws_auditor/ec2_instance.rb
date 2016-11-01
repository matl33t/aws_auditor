require_relative './instance_helper'

class Fraction
  attr_accessor :numerator, :denominator
  def initialize(numerator, denominator)
    @numerator = numerator
    @denominator = denominator
  end

  def to_s
    "#{@numerator}/#{@denominator}"
  end

  def difference
    @denominator - @numerator
  end

  def add(num)
    @numerator += num
  end

  def to_f
    @numerator.to_f / @denominator
  end
end

class Someclass
end

module SportNginAwsAuditor
  class EC2Instance < AwsInstance
    extend EC2Wrapper

    class << self
      attr_accessor :instances, :reserved_instances

      def compare(tag_name)
        differences = super(tag_name)
        differences[:unutilized_reserved].dup.each do |instance, ri_count|
          if instance.availability_zone == 'Region' && ri_count > 0
            # find matching insufficiently reserved permanent instances
            differences[:insufficiently_reserved_permanent].select { |_instance,v| instance.eql?(_instance, true) }.dup.each do |i, fraction|
              if ri_count >= fraction.difference
                ri_count -= fraction.difference
                fraction.numerator = fraction.denominator
                differences[:fully_reserved_permanent][i] = fraction
                differences[:insufficiently_reserved_permanent].delete(i)
              else
                ri_count = 0
                fraction.add(ri_count)
              end

              if ri_count == 0
                differences[:unutilized_reserved].delete(instance)
                break
              else
                differences[:unutilized_reserved][instance] = ri_count
              end
            end

            differences[:insufficiently_reserved_temporary].select { |_instance,v| instance.eql?(_instance, true) }.dup.each do |i, fraction|
              if ri_count >= fraction.difference
                ri_count -= fraction.difference
                fraction.numerator = fraction.denominator
                differences[:fully_reserved_temporary][i] = fraction
                differences[:insufficiently_reserved_temporary].delete(i)
              else
                ri_count = 0
                fraction.add(ri_count)
                break
              end

              if ri_count == 0
                differences[:unutilized_reserved].delete(instance)
                break
              else
                differences[:unutilized_reserved][instance] = ri_count
              end
            end
          end
        end
        differences
      end

      def get_instances(tag_name=nil)
        return @instances if @instances
        @instances = ec2.describe_instances.reservations.map do |reservation|
          reservation.instances.map do |instance|
            next unless instance.state.name == 'running'
            new(instance, tag_name)
          end.compact
        end.flatten.compact
        get_more_info
      end

      def get_reserved_instances
        return @reserved_instances if @reserved_instances
        @reserved_instances = ec2.describe_reserved_instances.reserved_instances.map do |ri|
          next unless ri.state == 'active'
          new(ri, nil, ri.instance_count)
        end.compact
      end

      def bucketize
        buckets = {}
        get_instances.map do |instance|
          name = instance.stack_name || instance.name
          if name
            buckets[name] = [] unless buckets.has_key? name
            buckets[name] << instance
          else
            puts "Could not sort #{instance.id}, as it has no stack_name or name"
          end
        end
        buckets.sort_by{|k,v| k }
      end

      def get_more_info
        get_instances.each do |instance|
          tags = ec2.describe_tags(:filters => [{:name => "resource-id", :values => [instance.id]}]).tags
          tags = Hash[tags.map { |tag| [tag[:key], tag[:value]]}.compact]
          instance.name = tags["Name"]
          instance.stack_name = tags["opsworks:stack"]
        end
      end
      private :get_more_info
    end

    attr_accessor :id, :name, :platform, :availability_zone, :instance_type, :count, :stack_name, :tag_value
    def initialize(ec2_instance, tag_name, count=1)
      if ec2_instance.class.to_s == "Aws::EC2::Types::ReservedInstances"
        self.id = ec2_instance.reserved_instances_id
        self.name = nil
        self.platform = platform_helper(ec2_instance.product_description)
        self.instance_type = ec2_instance.instance_type
        self.count = count
        self.stack_name = nil


        if ec2_instance.scope == 'Availability Zone'
          self.availability_zone = ec2_instance.availability_zone
        elsif ec2_instance.scope == 'Region'
          self.availability_zone = 'Region'
        end
      elsif ec2_instance.class.to_s == "Aws::EC2::Types::Instance"
        self.id = ec2_instance.instance_id
        self.name = nil
        self.platform = platform_helper((ec2_instance.platform || ''), ec2_instance.vpc_id)
        self.availability_zone = ec2_instance.placement.availability_zone
        self.instance_type = ec2_instance.instance_type
        self.count = count
        self.stack_name = nil

        # go through to see if the tag we're looking for is one of them
        if tag_name
          ec2_instance.tags.each do |tag|
            if tag.key == tag_name
              self.tag_value = tag.value
            end
          end
        end
      end
    end

    def no_reserved_instance_tag_value
      @tag_value
    end

    def to_s
      fields.values.join(' ')
    end

    def hash
      fields.hash
    end

    # Used to match Reserved Instances and EC2 Instances during comparison
    def eql?(other, ignore_az = false)
      if ignore_az
        rm_az = lambda { |f| f.delete('Availability Zone'); f }
        rm_az.call(fields) == rm_az.call(other.fields)
      else
        fields == other.fields
      end
    end

    def fields
      {
        'Platform' => @platform,
        'Availability Zone' => @availability_zone,
        'Instance Type' => @instance_type,
      }
    end

    def platform_helper(description, vpc=nil)
      platform = ''

      if description.downcase.include?('windows')
        platform << 'Windows'
      elsif description.downcase.include?('linux') || description.empty?
        platform << 'Linux'
      end

      if description.downcase.include?('vpc') || vpc
        platform << ' VPC'
      end

      return platform
    end
    private :platform_helper
  end
end
