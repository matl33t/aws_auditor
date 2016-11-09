module SportNginAwsAuditor
  class FractionalCount
    attr_accessor :numerator, :denominator

    def initialize(numerator, denominator)
      @numerator = numerator
      @denominator = denominator
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

    def to_s
      "#{@numerator}/#{@denominator}"
    end
  end
end
