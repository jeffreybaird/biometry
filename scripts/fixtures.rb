#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixture harness — PROJECT.md 0e.
#
# Validates the hand transcription in data/ and the reference loader together,
# before any spec is written against either. Run with:
#
#   bundle exec ruby scripts/fixtures.rb
#
# Fixtures backed by a table (NICHD, WHO) are checked now: they need nothing
# but the CSV. Fixtures backed by an equation (Hadlock 1991, INTERGROWTH LMS,
# the 1985 EFW formulas) are reported PENDING, because the code that evaluates
# them arrives in slices 3 and 4. They are listed rather than skipped silently
# so the count cannot be mistaken for full coverage.

require_relative '../lib/biometry'
require_relative 'fixtures/report'
require_relative 'fixtures/manifests'
require_relative 'fixtures/nichd'
require_relative 'fixtures/who'
require_relative 'fixtures/intergrowth'

report = Fixtures::Report.new($stdout)

Fixtures::Manifests.call(report)
Fixtures::Nichd.call(report)
Fixtures::Who.call(report)
Fixtures::Intergrowth.call(report)

report.pending_equation_fixtures
exit report.summary
