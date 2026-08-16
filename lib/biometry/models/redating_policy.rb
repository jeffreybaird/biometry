# frozen_string_literal: true

module Biometry
  # The redating policy on offer: whose thresholds, which paper, and — carried
  # verbatim — what its manifest admits is unverified about them. A consumer
  # offering redating has to be able to say that much.
  RedatingPolicy = Data.define(:standard, :citation, :known_issues)
end
