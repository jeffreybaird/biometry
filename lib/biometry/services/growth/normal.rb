# frozen_string_literal: true

module Biometry
  module Services
    module Growth
      # The standard normal CDF, in one place.
      #
      # Both equation standards turn a Z-score into a percentile, and doing
      # that twice is two chances to differ in the tails — which is exactly
      # where this library gets read.
      #
      # Nothing here is a clinical constant; these are properties of the normal
      # distribution. Math.erfc is used rather than a series expansion because
      # it stays accurate far into the tails, where a naive implementation
      # returns 0 or 1 and turns a 10-week 35 g median into a NaN downstream.
      module Normal
        module_function

        def cdf(z) = Math.erfc(-z / Math.sqrt(2)) / 2
      end
    end
  end
end
