require 'highline'

module SportNginAwsAuditor
  module Output
    def self.terminal
      @terminal ||= HighLine.new
    end

    def self.ask(*args, &block)
      terminal.ask(*args, &block)
    end
  end
end
