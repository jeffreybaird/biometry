# frozen_string_literal: true

module Biometry
  module Services
    module Report
      # Turns the scans a report is about into studies the renderer can print.
      #
      # This is arithmetic about a scan rather than command plumbing, which is
      # why it does not live in the command.
      class Studies
        def initialize(rows:)
          @rows = rows
        end

        def call(scans, ga:, at:, sex: nil, stratum: nil)
          scans.map do |scan|
            gestation = shifted(ga, at, scan.date)
            Study.new(scan: scan, ga: gestation,
                      growth: @rows.call(scan: scan, ga: gestation, sex: sex, stratum: stratum))
          end
        end

        private

        # Each study is read at the gestation on its own date. A scan taken
        # weeks earlier, read at the gestation the caller supplied, yields a
        # percentile wrong by exactly those days — and wrong in the most
        # convincing way available, four standards agreeing with each other
        # about a fetus older than the one measured.
        #
        # Pure date arithmetic: a gestation advances one day per day, which is
        # what it means. No clinical constant enters it.
        def shifted(supplied, reference_date, observed_on)
          return supplied if observed_on == reference_date

          GestationalAge.new(days: supplied.days - (reference_date - observed_on).to_i)
        end
      end
    end
  end
end
