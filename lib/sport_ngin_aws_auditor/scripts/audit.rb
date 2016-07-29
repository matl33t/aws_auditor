require 'highline/import'
require 'net/smtp'
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
        options[:tag_name] = nil if options[:no_tag]



        output = {}
        output[:EC2] = EC2Instance.audit(options) if options[:ec2] || no_selection
        output[:RDS] = RDSInstance.audit(options) if options[:rds] || no_selection
        output[:Cache] = CacheInstance.audit(options) if options[:cache] || no_selection
        full_output = output.values.join(' ')

        if options[:slack]
          puts "Condensed results from this audit will print into Slack instead of directly to an output."
          print_to_slack(output)
        elsif options[:html]
          puts wrap_html(full_output)
        elsif options[:email]
          send_email(wrap_html(full_output))
        else
          output.each do |aws_service, out|
            puts out
          end
        end
      end

      def wrap_html(body)
        header = "<!DOCTYPE html><html><head>\n"
        header << "<title>Reserved Instances Audit Results</title>\n"
        header << "</head><body>\n"
        header << "<h1>Reserved Instances Audit for #{environment} on #{Time.new.strftime('%Y-%m-%d')}</h1>\n"
        footer = "</body></html>\n"
        header + body + footer
      end

      def send_email(message)
        from = 'aws_auditor@lumoslabs.com'
        email_recipients = ['mleung@lumoslabs.com']
        to = email_recipients.map { |recipient| "<#{recipient}>" }.join(', ')
        email = <<MESSAGE_END
From: <#{from}>
To: #{to}
MIME-Version: 1.0
Content-type: text/html
Subject: AWS Auditor Reserved Instances Report

        #{message}
MESSAGE_END

        Net::SMTP.start('localhost') { |s| s.send_message(email, from, email_recipients) }
      end

      def print_to_slack(output)
        output.each do |class_type, out|
          if out.empty?
            slack_job = NotifySlack.new("All #{class_type} instances for #{environment} are up to date.")
            slack_job.perform
          else
            to_print = "Some #{class_type} instances for #{environment} are out of sync:\n"
            slack_job = NotifySlack.new(to_print, out)
            slack_job.perform
          end
        end
      end
    end
  end
end
