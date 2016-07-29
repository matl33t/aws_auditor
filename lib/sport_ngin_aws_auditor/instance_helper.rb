require 'pastel'
require 'tty-table'

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
        instance_hash[instance] = instance_hash.has_key?(instance) ? instance_hash[instance] + instance.count : instance.count
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
      permanent_instance_counts.each do |instance, instance_count|
        ri_count = reserved_instance_counts[instance] || 0
        if ri_count > instance_count
          differences[:fully_reserved_permanent][instance] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[instance] -= instance_count
        elsif ri_count == instance_count
          differences[:fully_reserved_permanent][instance] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts.delete(instance)
        else
          differences[:insufficiently_reserved_permanent][instance] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(instance)
        end
      end

      temporary_instance_counts.each do |instance, instance_count|
        ri_count = reserved_instance_counts[instance] || 0
        if ri_count > instance_count
          differences[:fully_reserved_temporary][instance] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts[instance] -= instance_count
        elsif ri_count > instance_count
          differences[:fully_reserved_temporary][instance] = "#{instance_count}/#{instance_count}"
          reserved_instance_counts.delete(instance)
        else
          differences[:insufficiently_reserved_temporary][instance] = "#{ri_count}/#{instance_count}"
          reserved_instance_counts.delete(instance)
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
        generate_slack_output(data)
      elsif options[:html] || options[:email]
        generate_html_output(data)
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
      output = "#{header}\n"
      data.each do |type, counts|
        next if counts.empty?
        table_header = nil
        rows = []
        counts.sort_by { |instance, count| Rational(count) }.reverse.each do |instance, count|
          table_header ||= instance.fields.keys + ['Counts']
          rows << instance.fields.values + [count]
        end
        table = TTY::Table.new(header: table_header, rows: rows)
        type_str = type.to_s.split('_').map(&:capitalize).join(' ')

        output << "#{type_str} Instances\n"
        output << Pastel.new.decorate(table.render(:ascii, padding: [0, 4]), color_severity(type)) + "\n"
      end
      output
    end

    def color_severity(instance_type, format=:text)
      case instance_type
      when :fully_reserved_permanent
        format == :text ? :green : '#82E0AA'
      when :insufficiently_reserved_permanent
        format == :text ? :yellow : '#F9E79F'
      when :fully_reserved_temporary
        format == :text ? :blue : '#AED6F1'
      when :insufficiently_reserved_temporary
        format == :text ? :blue : '#AED6F1'
      when :unutilized_reserved
        format == :text ? :red : '#F1948A'
      else
        format == :text ? :white : '#F2F3F4'
      end
    end

    def generate_html_output(data)
      aws_service = self.name.split('::').last.sub('Instance', '')
      html = ''
      current_type = nil
      padding = "padding: 2px 15px"

      data.each do |type, counts|
        next if counts.empty?

        if current_type != type
          type_str = type.to_s.split('_').map(&:capitalize).join(' ')
          html << "<h2 style=\"background-color:#{color_severity(type, :hex)}\">#{aws_service}: #{type_str} Instances</h2>"
          current_type = type
        end

        table_header = []
        table_data = []
        html << "<table style=\"background-color:#e8e8e8; border: 1px solid black;\"><tbody>\n"
        counts.sort_by { |instance, count| Rational(count) }.reverse.each do |instance, count|
          table_data.push("<tr>\n")
          if table_header.empty?
            instance.fields.keys.each do |field_name|
              table_header.push("<td style=\"#{padding}; border-right: 1px solid black;\">#{field_name}</td>\n")
            end
            table_header.push("<td style=\"#{padding};\">Counts</td>\n")
          end
          instance.fields.each do |field_name, field|
            table_data.push("<td style=\"#{padding}; border-right: 1px solid black;\">#{field}</td>\n")
          end
          table_data.push("<td style=\"#{padding};\">#{count}</td></tr>\n")
        end
        html << table_header.join
        html << table_data.join
        html << "</tbody></table><br>\n"
      end

      html
    end

    def generate_slack_output(data)
      attachments = []
      data.each do |type, counts|
        next if counts.empty?
        if type == :insufficiently_reserved_permanent || type == :unutilized_reserved
          counts.sort_by { |instance, count| Rational(count) }.reverse.each do |instance, count|
            attachments.push({
              color: color_severity(type, :hex),
              fallback: "#{instance}: #{count}",
              text: "#{instance}: #{count}"
            })
          end
        end
      end

      attachments
    end

    # Assuming the value of the tag is in the form: 01/01/2000 like a date
    def filter_instances_with_tags(instances)
      instances.select do |instance|
        value = gather_instance_tag_date(instance)
        value && (Date.today.to_s < value.to_s)
      end
    end

    # Assuming the value of the tag is in the form: 01/01/2000 like a date
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
