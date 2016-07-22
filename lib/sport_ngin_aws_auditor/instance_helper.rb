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

    # Generates a hash with { instance type => count }
    # by calculating the difference of on-demand and reserved instances
    def compare(tag_name)
      differences = {
        fully_reserved_permanent: {},
        insufficiently_reserved_permanent: {},
        fully_reserved_temporary: {},
        insufficiently_reserved_temporary: {},
        unutilized_reserved: {}
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
          differences[:fully_reserved_permanent][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[key] -= instance_count
        elsif ri_count == instance_count
          differences[:fully_reserved_permanent][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        else
          differences[:insufficiently_reserved_permanent][key] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        end
      end

      temporary_instance_counts.each do |key, instance_count|
        ri_count = reserved_instance_counts[key] || 0
        if ri_count > instance_count
          differences[:fully_reserved_temporary][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[key] -= instance_count
        elsif ri_count > instance_count
          differences[:fully_reserved_temporary][key] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        else
          differences[:insufficiently_reserved_temporary][key] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(key)
        end
      end

      differences[:unutilized_reserved] = reserved_instance_counts
      differences
    end

    def audit(options)
      data = {}
      if options[:instances]
        instances = get_instances(options[:tag_name])
        permanent_instances = filter_instance_without_tags(instances)
        temporary_instances = filter_instances_with_tags(instances)
        data[:permanent] = instance_count_hash(permanent_instances)
        data[:temporary] = instance_count_hash(temporary_instances)
      elsif options[:reserved]
        data[:reserved] = instance_count_hash(get_reserved_instances)
      else
        data = compare(options[:tag_name])
      end

      if options[:slack]
        generate_slack_output(data, class_type, environment)
      elsif options[:html] || options[:email]
        puts generate_html_output(data)
      else
        generate_console_output(data)
      end
    end

    def header(length = 50)
      type = self.name.split('::').last.sub('Instance', '')
      half_length = (length - type.size)/2.0 - 1
      [
        "*" * length,
        "*" * half_length.floor + " #{type} " + "*" * half_length.ceil,
        "*" * length
      ].join("\n")
    end

    private

    def generate_console_output(data)
      puts header
      data.each do |type, counts|
        puts "#{type.capitalize} Instances" unless counts.empty?
        counts.sort_by { |name, count| Rational(count) }.reverse.each do |name, count|
          say "<%= color(' ↳> #{name}: #{count}', :#{color_severity(type)}) %>"
        end
      end
    end

    def color_severity(instance_type, format=:text)
      case instance_type
      when :fully_reserved_permanent
        format == :text ? 'green' : '#82E0AA'
      when :insufficiently_reserved_permanent
        format == :text ? 'yellow' : '#F9E79F'
      when :fully_reserved_temporary
        format == :text ? 'blue' : '#AED6F1'
      when :insufficiently_reserved_temporary
        format == :text ? 'blue' : '#AED6F1'
      when :unutilized_reserved
        format == :text ? 'red' : '#F1948A'
      else
        format == :text ? 'white' : '#F2F3F4'
      end
    end

    def generate_html_output(data)
      td20 = 'td width=20%'
      td80 = 'td width=80%'
      aws_service = self.name.split('::').last.sub('Instance', '')

      html << "<h2>#{aws_service} Instances</h2>\n"

      current_type = nil
      data.each do |type, counts|
        next if counts.empty?

        html << "<table width=100%><tbody>\n"
        if current_type != type
          type_str = type.to_s.split('_').map(&:capitalize).join(' ')
          html << "<tr bgcolor=#{color_severity(type, :hex)}>\n"
          html << "<#{td80}>#{type_str} Instances</td></tr>\n"
          current_type = type
        end

        counts.sort_by { |name, count| Rational(count) }.reverse.each do |name, count|
          html << "<tr bgcolor=#e8e8e8>\n"
          html << "<#{td80}>#{name}</td><#{td20}>#{count}</td></tr>\n"
        end
        html << "</tbody></table><br>\n"
      end

      header + html + footer
    end
=begin
    class HelperThing
      def initialize
        @type = :unutilized
        @ondemand_count = Integer
        @reserved_count = Integer
        @instance = Instance
        @instance_type
      end

      def fraction
        @count
      end

      def difference

      end
    end
=end

    def generate_slack_output(data)
      attachments = []
      data.each do |type, counts|
        next if counts.empty?
        if type == :insufficiently_reserved_permanent || type == :unutilized_reserved
          counts.sort_by { |name, count| Rational(count) }.reverse.each do |name, count|
            attachments += {
              color: color_severity(type, :hex),
              fallback: "#{name}: #{count}",
              text: "#{name}: #{count}"
            }
          end
        end
      end

      attachments
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
