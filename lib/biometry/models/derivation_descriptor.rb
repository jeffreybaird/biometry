# frozen_string_literal: true

module Biometry
  # One way the library dates a pregnancy, cited as the dating service itself
  # cites it.
  DerivationDescriptor = Data.define(:derivation, :standard, :citation)
end
