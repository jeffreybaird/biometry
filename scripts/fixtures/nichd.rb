# frozen_string_literal: true

module Fixtures
  # NICHD is a table, so its fixtures are checkable at slice 0: they assert
  # that data/percentiles/nichd.csv agrees with the values quoted in
  # data/nichd.yml. Two hand transcriptions of Buck Louis Table 2 agreeing.
  module Nichd
    CENTILES = %i[p3 p5 p10 p50 p90 p95 p97].freeze
    QUOTED = %i[p5 p50 p95].freeze
    FITTED_FROM = 15

    module_function

    def call(report)
      report.section('NICHD (table-backed — checkable now)')
      manifest = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'nichd.yml')
      rows = Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/nichd.csv')

      manifest[:fixtures].each { |fixture| run(report, fixture, rows) }
      check_extrapolated_rows_present(report, rows)
    end

    def run(report, fixture, rows)
      return integrity(report, rows) if fixture[:assert]

      week = fixture[:name][/\d+/].to_i
      fixture[:expect].each do |group, quoted|
        row = find(rows, group.to_s, week)
        report.check("#{week}w #{group} p5/p50/p95", QUOTED.map { |c| row[c] }, quoted)
      end
    end

    # Table 2 prints whole grams. Below ~12 weeks the median is under 60 g and
    # adjacent centiles round together (white@10w prints p3 = p5 = 23), so the
    # manifest's "increases left to right" holds as non-decreasing everywhere
    # and strictly within the fitted range. Every observed tie is in weeks
    # 10-14, which slice 4 rejects anyway.
    def integrity(report, rows)
      rows_never_decrease(report, rows)
      rows_strictly_increase_where_fitted(report, rows)
      columns_increase_with_ga(report, rows)
    end

    def rows_never_decrease(report, rows)
      offenders = rows.reject { |row| ordered?(row, :>=) }
      report.check('centiles never decrease left to right', labels(offenders), [])
    end

    def rows_strictly_increase_where_fitted(report, rows)
      fitted = rows.select { |row| row[:ga_weeks] >= FITTED_FROM }
      offenders = fitted.reject { |row| ordered?(row, :>) }
      report.check('centiles strictly increase within fitted range', labels(offenders), [])
    end

    def columns_increase_with_ga(report, rows)
      offenders = rows.group_by { |row| row[:group] }.reject { |_, g| column_monotonic?(g) }
      report.check('every centile column increases with GA', offenders.keys, [])
    end

    def labels(rows) = rows.map { |row| label(row) }

    def ordered?(row, operator)
      CENTILES.map { |c| row[c] }.each_cons(2).all? { |a, b| b.public_send(operator, a) }
    end

    # Weeks 10-14 are spline extrapolation outside the fitted range. The CSV
    # keeps them so it can be diffed against the published table; the slice 4
    # loader must reject them. Assert they are still there to be filtered.
    def check_extrapolated_rows_present(report, rows)
      below = rows.count { |row| row[:ga_weeks] < FITTED_FROM }
      report.check('weeks 10-14 retained in CSV for the loader to filter', below, 20)
    end

    def column_monotonic?(group_rows)
      ordered = group_rows.sort_by { |row| row[:ga_weeks] }
      CENTILES.all? { |c| monotonic?(ordered.map { |row| row[c] }) }
    end

    def monotonic?(values) = values.each_cons(2).all? { |a, b| b > a }

    def find(rows, group, week)
      rows.find { |row| row[:group] == group && row[:ga_weeks] == week } ||
        raise("nichd.csv has no row for #{group} at #{week}w")
    end

    def label(row) = "#{row[:group]}@#{row[:ga_weeks]}w"
  end
end
