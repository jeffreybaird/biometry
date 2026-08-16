# frozen_string_literal: true

module Biometry
  # One composed report: the dating derivations (each a Result), the supplied
  # gestation, the studies read from each scan, and the redating decision when
  # one was asked for (nil otherwise).
  #
  # The members are exactly the arguments Services::Report::Document takes, so
  # Data's own #to_h is the hand-off — no second spelling of the same list.
  Report = Data.define(:dating, :ga, :studies, :redating) do
    # Exit 1 only when nothing at all could be reported. The refusals are the
    # result and still print; CRL and biometry always refuse, so any other
    # rule would make "nothing reportable" permanent.
    def reportable?
      rows = studies.flat_map(&:growth)
      dating.values.any?(&:success?) || rows.any? { |row| row[:report].success? }
    end
  end
end
