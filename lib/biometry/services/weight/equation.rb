# frozen_string_literal: true

module Biometry
  module Services
    module Weight
      # A Hadlock EFW regression, parsed from the `equation:` string in
      # data/hadlock_1985.yml.
      #
      # It is parsed rather than hand-transcribed because those strings are the
      # only place the coefficients exist — hadlock_1985.yml publishes no
      # `coefficients:` block — and retyping one into Ruby would be supplying a
      # clinical constant from outside data/.
      #
      # The grammar is deliberately closed: a sum of signed terms, each a
      # numeric coefficient optionally multiplied by named variables. No
      # parentheses, no exponents, no division. Anything else is refused rather
      # than partly understood, which is what keeps INTERGROWTH's equation —
      # parentheses, a cube and a natural log — from being silently mangled
      # into a plausible wrong number.
      class Equation
        Term = Data.define(:coefficient, :variables)

        # A coefficient, then zero or more `* NAME` factors. Anchored, so a
        # term containing anything else fails to match rather than matching a
        # prefix of itself.
        TERM = /\A(\d+(?:\.\d+)?)((?:\s*\*\s*[a-z_][a-z0-9_]*)*)\z/i

        # Splits the right-hand side at the signs, keeping each sign with the
        # term it belongs to. A leading term with no sign is positive.
        SIGNED_TERM = /[+-]?\s*[^+-]+/

        def self.parse(string)
          right = right_hand_side(string)
          new(right.scan(SIGNED_TERM).map { |chunk| term(chunk, string) })
        end

        def self.right_hand_side(string)
          right = string.split('=', 2)[1]
          raise_malformed(string) if right.nil?

          # An empty right-hand side would otherwise scan to zero terms and
          # evaluate to 0 — a wrong weight rather than a refusal.
          collapsed = right.gsub(/\s+/, ' ').strip
          raise_malformed(string) if collapsed.empty?

          collapsed
        end

        def self.term(chunk, string)
          signed = chunk.strip
          sign = signed.start_with?('-') ? -1 : 1
          match = TERM.match(signed.delete_prefix('-').delete_prefix('+').strip)
          raise_malformed(string) unless match

          Term.new(coefficient: sign * Float(match[1]), variables: names(match[2]))
        end

        def self.names(factors)
          factors.scan(/[a-z_][a-z0-9_]*/i).map { |name| name.downcase.to_sym }
        end

        def self.raise_malformed(string)
          raise MalformedReferenceData,
                "could not parse equation: #{string.inspect}. The grammar is a sum of " \
                'signed terms, each a number optionally multiplied by named variables.'
        end

        private_class_method :right_hand_side, :term, :names, :raise_malformed

        def initialize(terms)
          @terms = terms.freeze
          freeze
        end

        def variables = @terms.flat_map(&:variables).uniq

        # Returns the right-hand side only. Applying the left-hand side's
        # transform — 10** for log10, exp for ln — is the caller's job, because
        # only the caller knows which one the manifest declared.
        def evaluate(values)
          @terms.sum do |term|
            term.variables.reduce(term.coefficient) { |acc, name| acc * values.fetch(name) }
          end
        end
      end
    end
  end
end
