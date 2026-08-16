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
      # The quantile is Wichura's AS241 (PPND16, Applied Statistics 37(3),
      # 1988): three rational approximations — central, tail, far tail —
      # accurate to ~1e-16, so a centile asked for at the 3rd and read back
      # through cdf lands on the 3rd, not near it. The coefficients are the
      # algorithm's own, properties of the distribution like erfc above.
      module Normal
        module_function

        def cdf(z) = Math.erfc(-z / Math.sqrt(2)) / 2

        # Strictly inside (0, 1): probability 0 or 1 has no finite quantile,
        # and a caller asking for one has a bug — the services guard centile
        # inputs with Results long before this is reached.
        def inverse_cdf(probability)
          unless probability.is_a?(Numeric) && probability.positive? && probability < 1
            raise ArgumentError, "probability must be strictly between 0 and 1: #{probability}"
          end

          q = probability - 0.5
          q.abs <= 0.425 ? central(q) : tail(probability, q)
        end

        def central(shift)
          r = 0.180625 - (shift * shift)
          shift * ratio(CENTRAL_NUM, CENTRAL_DEN, r)
        end

        def tail(probability, shift)
          r = Math.sqrt(-Math.log(shift.negative? ? probability : 1 - probability))
          z = r <= 5 ? ratio(TAIL_NUM, TAIL_DEN, r - 1.6) : ratio(FAR_NUM, FAR_DEN, r - 5)
          shift.negative? ? -z : z
        end

        def ratio(numerator, denominator, point)
          horner(numerator, point) / horner(denominator, point)
        end

        def horner(coefficients, point)
          coefficients.reverse.reduce(0.0) { |sum, coefficient| (sum * point) + coefficient }
        end

        # AS241 PPND16 coefficients, ascending powers; denominators lead with 1.
        CENTRAL_NUM = [3.3871328727963666080e0, 1.3314166789178437745e2,
                       1.9715909503065514427e3, 1.3731693765509461125e4,
                       4.5921953931549871457e4, 6.7265770927008700853e4,
                       3.3430575583588128105e4, 2.5090809287301226727e3].freeze
        CENTRAL_DEN = [1.0, 4.2313330701600911252e1, 6.8718700749205790830e2,
                       5.3941960214247511077e3, 2.1213794301586595867e4,
                       3.9307895800092710610e4, 2.8729085735721942674e4,
                       5.2264952788528545610e3].freeze
        TAIL_NUM = [1.42343711074968357734e0, 4.63033784615654529590e0,
                    5.76949722146069140550e0, 3.64784832476320460504e0,
                    1.27045825245236838258e0, 2.41780725177450611770e-1,
                    2.27238449892691845833e-2, 7.74545014278341407640e-4].freeze
        TAIL_DEN = [1.0, 2.05319162663775882187e0, 1.67638483018380384940e0,
                    6.89767334985100004550e-1, 1.48103976427480074590e-1,
                    1.51986665636164571966e-2, 5.47593808499534494600e-4,
                    1.05075007164441684324e-9].freeze
        FAR_NUM = [6.65790464350110377720e0, 5.46378491116411436990e0,
                   1.78482653991729133580e0, 2.96560571828504891230e-1,
                   2.65321895265761230930e-2, 1.24266094738807843860e-3,
                   2.71155556874348757815e-5, 2.01033439929228813265e-7].freeze
        FAR_DEN = [1.0, 5.99832206555887937690e-1, 1.36929880922735805310e-1,
                   1.48753612908506148525e-2, 7.86869131145613259100e-4,
                   1.84631831751005468180e-5, 1.42151175831644588870e-7,
                   2.04426310338993978564e-15].freeze
      end
    end
  end
end
