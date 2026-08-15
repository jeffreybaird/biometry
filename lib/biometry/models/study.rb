# frozen_string_literal: true

module Biometry
  # One study, as a report carries it.
  #
  # A message may report more than one, and each is read at the gestation on
  # its own date — so the gestation belongs to the study rather than to the
  # report. A single gestation at the top of a two-study report is right for
  # one of them and wrong by exactly the days between them for the other, and
  # wrong in the most convincing way available: four standards agreeing with
  # each other about a fetus weeks older than the one measured.
  #
  # The rows travel with it for the same reason. They were read at that
  # gestation, from that scan, and rows detached from the study they belong to
  # are a table a reader cannot attribute.
  #
  # The date is the scan's rather than a second copy of it: two places to write
  # a date is one place for them to disagree.
  Study = Data.define(:scan, :ga, :growth) do
    def date = scan.date
  end
end
