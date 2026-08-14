# frozen_string_literal: true

module Biometry
  # A warning quoted from a guideline, carried verbatim.
  #
  # The text is the guideline's, not ours, which is why nothing reworders or
  # summarises it. The third-trimester caveat says redating a small fetus
  # "risks masking growth restriction" — a statement about what the action
  # risks, not a classification of any particular pregnancy, and it is the
  # clinically load-bearing half of that band's answer.
  Caveat = Data.define(:id, :text) do
    def to_s = text
  end
end
