# frozen_string_literal: true

module Biometry
  # Everything the library serves, described for a consumer that has supplied
  # nothing yet: the growth standards, the weight formulas, the dating
  # derivations and the redating policy, each naming its paper.
  Catalog = Data.define(:growth_standards, :efw_formulas, :dating_methods, :redating_policy)
end
