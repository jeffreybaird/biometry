# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module CLI
    # Builds one printed row per chart reading.
    #
    # Formula and chart are paired, so each standard is read from the weight
    # its own manifest names — three distinct EFW values across four
    # standards, not one weight compared four ways.
    #
    # A chart that could not be read keeps its row and carries the Failure. A
    # silently short table looks complete when it is not, which is the same
    # reason the services refuse rather than skip.
    class GrowthRows
      include Dry::Monads[:result]

      # Each chart's paired formula, as its manifest states it.
      CHARTS = { intergrowth21: :intergrowth, hadlock_1991: :hadlock_bpd_hc_ac_fl,
                 who: :hadlock_hc_ac_fl, nichd: :hadlock_hc_ac_fl }.freeze

      def initialize(manifests:, tables:)
        @manifests = manifests
        @tables = tables
      end

      def call(scan:, ga:, sex: nil, stratum: nil)
        weights = weigh(scan)
        CHARTS.flat_map do |standard, formula|
          rows(standard, weights[formula], ga: ga, sex: sex, stratum: stratum)
        end
      end

      private

      attr_reader :manifests, :tables

      def weigh(scan)
        Services::Weight::AllFormulas
          .new(hadlock: manifests[:hadlock_1985], intergrowth: manifests[:intergrowth21])
          .call(scan).value!
      end

      # NICHD answers an unsupplied stratum with one Percentile per chart, so
      # one call becomes four rows. That is the adapter's decision about its
      # own data; this only unpacks it.
      # The citation comes from the manifest rather than from the reading, so
      # a row that could not be read is still attributable. A row on the page
      # whose paper is not in the footer leaves a reader unable to check it.
      def rows(standard, weight, **query)
        report = weight.success? ? read(standard, weight.value!, **query) : weight
        row = { standard: standard, weight: weight, report: report,
                citation: manifests[standard].dig(:source, :citation) }
        return [row] unless standard == :nichd && report.success?

        report.value!.map { |percentile| row.merge(report: Success(percentile)) }
      end

      def read(standard, estimate, ga:, sex:, stratum:)
        case standard
        when :who then chart(standard).call(estimate: estimate, ga: ga, sex: sex)
        when :nichd then chart(standard).call(estimate: estimate, ga: ga, stratum: stratum)
        else chart(standard).call(estimate: estimate, ga: ga)
        end
      end

      def chart(standard)
        case standard
        when :intergrowth21 then Services::Growth::Intergrowth.new(manifest: manifests[standard])
        when :hadlock_1991 then Services::Growth::Hadlock1991.new(manifest: manifests[standard])
        when :who then table_chart(Services::Growth::Who, standard, :who)
        else table_chart(Services::Growth::Nichd, standard, :nichd)
        end
      end

      def table_chart(klass, standard, table)
        klass.new(manifest: manifests[standard], table: tables[table])
      end
    end
  end
end
