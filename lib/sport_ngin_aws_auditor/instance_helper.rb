module SportNginAwsAuditor
	module InstanceHelper

		def instance_hash
      Hash[get_instances.map { |instance| instance.nil? ? next : [instance.id, instance]}.compact]
    end

    def reserved_instance_hash
      Hash[get_reserved_instances.map { |instance| instance.nil? ? next : [instance.id, instance]}.compact]
    end

    # Builds a hash from instance strings containing total counts
    def instance_count_hash(instances)
      instance_hash = Hash.new()
      instances.each do |instance|
        next if instance.nil?
        instance_hash[instance.to_s] = instance_hash.has_key?(instance.to_s) ? instance_hash[instance.to_s] + instance.count : instance.count
      end if instances
      instance_hash
    end

    # generates a hash with { instance type => count }
    def compare(tag_name)
      differences = {
        permanent: {},
        temporary: {},
        unutilized: {}
      }
      instances = get_instances(tag_name)

      temporary_instances = filter_instances_with_tags(instances)
      permanent_instances = filter_instance_without_tags(instances)

      permanent_instance_counts = instance_count_hash(permanent_instances)
      temporary_instance_counts = instance_count_hash(temporary_instances)
      reserved_instance_counts = instance_count_hash(get_reserved_instances)

      # generate diff hash
      permanent_instance_counts.each do |key, instance_count|
        ri_count = reserved_instance_counts[key] || 0
        if ri_count > instance_count
          differences[:permanent][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[key] -= instance_count
        else
          differences[:permanent][key] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        end
      end

      temporary_instance_counts.each do |key, instance_count|
        ri_count = reserved_instance_counts[key] || 0
        if ri_count > instance_count
          differences[:temporary][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[key] -= instance_count
        else
          differences[:temporary][key] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        end
      end

      differences[:unutilized] = reserved_instance_counts
      differences
    end

    # assuming the value of the tag is in the form: 01/01/2000 like a date
    def filter_instances_with_tags(instances)
      instances.select do |instance|
        value = gather_instance_tag_date(instance)
        value && (Date.today.to_s < value.to_s)
      end
    end

    # assuming the value of the tag is in the form: 01/01/2000 like a date
    def filter_instance_without_tags(instances)
      instances.select do |instance|
        value = gather_instance_tag_date(instance)
        value.nil? || (Date.today.to_s >= value.to_s)
      end
    end

    def gather_instance_tag_date(instance)
      value = instance.no_reserved_instance_tag_value
      unless value.nil?
        date_hash = Date._strptime(value, '%m/%d/%Y')
        value = Date.new(date_hash[:year], date_hash[:mon], date_hash[:mday]) if date_hash
      end
      value
    end
	end
end
