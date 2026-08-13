# frozen_string_literal: true

module Biometry
  # Base for every error this library raises. Expected failures are Results,
  # not exceptions; anything descending from this is a bug or an
  # unrecoverable condition, and exe/ maps it to exit code 70.
  class Error < StandardError
  end

  # Raised when a reference file under data/ carries `verified: false`.
  # Deliberately not a Result: no caller should branch on it.
  class UnverifiedReferenceData < Error
  end

  # Raised when a reference file is absent or cannot be parsed.
  class MalformedReferenceData < Error
  end
end
