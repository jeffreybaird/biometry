# frozen_string_literal: true

module Fixtures
  # WHO is a table, so its fixtures are checkable at slice 0. Also asserts the
  # shape the sex-specific tables actually have: Tables 14 and 15 omit the
  # 2.5th and 97.5th centiles, and that absence is what makes
  # :unsupported_centile a real path in slice 4 rather than a hypothetical.
  module Who
    CENTILES = %i[p2_5 p5 p10 p25 p50 p75 p90 p95 p97_5].freeze
    SEX_SPECIFIC_OMITS = %i[p2_5 p97_5].freeze

    module_function

    def call(report)
      report.section('WHO (table-backed — checkable now)')
      manifest = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'who.yml')
      rows = Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/who.csv')

      manifest[:fixtures].each { |fixture| run(report, fixture, rows) }
      omitted_centiles(report, rows)
      integrity(report, rows)
    end

    def run(report, fixture, rows)
      case fixture[:name]
      when /p10 and p90/ then combined_centiles(report, fixture, rows)
      when /sex difference/ then sex_difference(report, fixture, rows)
      when /at 40 weeks/ then combined_at_term(report, fixture, rows)
      else report.fail_with(fixture[:name], 'harness has no check for this fixture')
      end
    end

    def combined_centiles(report, fixture, rows)
      fixture[:expect].each do |week, expected|
        row = find(rows, 'combined', week)
        report.check("combined #{week}w p10/p90", { p10: row[:p10], p90: row[:p90] }, expected)
      end
    end

    def sex_difference(report, fixture, rows)
      expected = fixture[:expect]
      female = find(rows, 'female', 37)[:p50]
      male = find(rows, 'male', 37)[:p50]
      report.check('37w p50 female', female, expected[:female])
      report.check('37w p50 male', male, expected[:male])
      report.check('37w p50 sex gap (g)', male - female, expected[:difference_g])
    end

    def combined_at_term(report, fixture, rows)
      row = find(rows, 'combined', 40)
      actual = { p2_5: row[:p2_5], p50: row[:p50], p97_5: row[:p97_5] }
      report.check('combined 40w p2.5/p50/p97.5', actual, fixture[:expect])
    end

    def omitted_centiles(report, rows)
      present = rows.reject { |row| row[:sex] == 'combined' }
                    .select { |row| SEX_SPECIFIC_OMITS.any? { |c| row[c] } }
      report.check('sex-specific tables omit p2.5 and p97.5', present.map { |r| label(r) }, [])
    end

    def integrity(report, rows)
      rows_increase(report, rows)
      female_below_male(report, rows)
    end

    def rows_increase(report, rows)
      offenders = rows.reject { |row| monotonic?(CENTILES.filter_map { |c| row[c] }) }
      report.check('centiles increase left to right in every row', labels(offenders), [])
    end

    def female_below_male(report, rows)
      females = rows.select { |row| row[:sex] == 'female' }
      offenders = females.reject { |row| row[:p50] < find(rows, 'male', row[:ga_weeks])[:p50] }
      report.check('female median below male at every week', labels(offenders), [])
    end

    def labels(rows) = rows.map { |row| label(row) }

    def monotonic?(values) = values.each_cons(2).all? { |a, b| b > a }

    def find(rows, sex, week)
      rows.find { |row| row[:sex] == sex && row[:ga_weeks] == week } ||
        raise("who.csv has no row for #{sex} at #{week}w")
    end

    def label(row) = "#{row[:sex]}@#{row[:ga_weeks]}w"
  end
end
