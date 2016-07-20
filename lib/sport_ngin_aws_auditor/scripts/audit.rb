require 'highline/import'
require_relative "../notify_slack"

module SportNginAwsAuditor
  module Scripts
    class Audit
      include AWSWrapper

      attr_accessor :environment, :options, :global_options

      def initialize(environment, options, global_options)
        self.environment = environment
        self.options = options
        self.global_options = global_options
      end

      def execute
        aws(environment, global_options[:aws_roles])
        no_selection = !(options[:ec2] || options[:rds] || options[:cache])

        if options[:no_tag]
          tag_name = nil
        else
          tag_name = options[:tag]
        end

        if options[:slack]
          puts "Condensed results from this audit will print into Slack instead of directly to an output."
        else
          puts "Gathering info, please wait..."
        end

        data = gather_data("EC2Instance", tag_name) if options[:ec2] || no_selection
        print_data(data, "EC2Instance") if options[:ec2] || no_selection

        data = gather_data("RDSInstance", tag_name) if options[:rds] || no_selection
        print_data(data, "RDSInstance") if options[:rds] || no_selection

        data = gather_data("CacheInstance", tag_name) if options[:cache] || no_selection
        print_data(data, "CacheInstance") if options[:cache] || no_selection
      end

      def gather_data(class_type, tag_name)
        klass = SportNginAwsAuditor.const_get(class_type)

        if options[:instances]
          data = {}
          instances = klass.get_instances(tag_name)
          permanent_instances = klass.filter_instance_without_tags(instances)
          temporary_instances = klass.filter_instances_with_tags(instances)
          data[:permanent] = klass.instance_count_hash(permanent_instances)
          data[:temporary] = klass.instance_count_hash(temporary_instances)
          data
        elsif options[:reserved]
          { reserved: klass.instance_count_hash(klass.get_reserved_instances) }
        else
          klass.compare(tag_name)
        end
      end

      def print_data(data, class_type)
        if options[:slack]
          print_to_slack(data, class_type, environment)
        elsif options[:reserved] || options[:instances]
          puts header(class_type)
          data.each do |type, counts|
            puts "#{type.capitalize} Instances" unless counts.empty?
            counts.each do |name, count|
              say "<%= color('  ↳> #{name}: #{count}', :white) %>"
            end
          end
        else
          puts header(class_type)
          data.each do |type, counts|
            puts "#{type.capitalize} Instances" unless counts.empty?
            counts.sort_by { |name, count| Rational(count) }.reverse.each do |name, count|
              if type == :unutilized
                say "<%= color('  ↳> #{name}: #{count}', :red) %>"
              elsif type == :temporary
                say "<%= color('  ↳> #{name}: #{count}', :blue) %>"
              elsif type == :permanent
                if Rational(count) == 1
                  say "<%= color('  ↳> #{name}: #{count}', :green) %>"
                else
                  say "<%= color('  ↳> #{name}: #{count}', :yellow) %>"
                end
              end
            end
          end
        end
      end

      def print_to_slack(instances_hash, class_type, environment)
        discrepancy_hash = Hash.new
        instances_hash.each do |key, value|
          if !(value == 0) && !(key.include?(" with tag"))
            discrepancy_hash[key] = value
          end
        end

        if discrepancy_hash.empty?
          slack_job = NotifySlack.new("All #{class_type} instances for #{environment} are up to date.")
          slack_job.perform
        else
          print_discrepancies(discrepancy_hash, class_type)
        end
      end

      def print_discrepancies(discrepancy_hash, class_type)
        to_print = "Some #{class_type} instances for #{environment} are out of sync:\n"
        to_print << "#{header(class_type)}\n"

        discrepancy_hash.each do |key, value|
          to_print << "#{key}: #{value}\n"
        end

        slack_job = NotifySlack.new(to_print)
        slack_job.perform
      end

      def header(type, length = 50)
        type.upcase!.slice! "INSTANCE"
        half_length = (length - type.length)/2.0 - 1
        [
          "*" * length,
          "*" * half_length.floor + " #{type} " + "*" * half_length.ceil,
          "*" * length
        ].join("\n")
      end
    end
  end
end
