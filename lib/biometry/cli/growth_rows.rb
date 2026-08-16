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

      # Each chart's paired formula, as its manifest states it. Hadlock 1991
      # appears twice because its dispersion is contested (12.7% in the
      # abstract, 13.3% implied by Table 1; see the manifest's
      # `dispersion_contested` known_issue) and this library reports both
      # sides of a live dispute rather than picking one.
      CHARTS = { intergrowth21: :intergrowth,
                 hadlock_1991_equation: :hadlock_bpd_hc_ac_fl,
                 hadlock_1991_table: :hadlock_bpd_hc_ac_fl,
                 who: :hadlock_hc_ac_fl, nichd: :hadlock_hc_ac_fl }.freeze

      # Both Hadlock variants read the one hadlock_1991 manifest.
      MANIFEST_KEYS = { hadlock_1991_equation: :hadlock_1991,
                        hadlock_1991_table: :hadlock_1991 }.freeze

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
                citation: manifest_for(standard).dig(:source, :citation) }
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
        when :hadlock_1991_equation, :hadlock_1991_table then hadlock_variant(standard)
        when :who then table_chart(Services::Growth::Who, standard, :who)
        else table_chart(Services::Growth::Nichd, standard, :nichd)
        end
      end

      # The variant name is the tail of the chart id; the manifest's
      # `variants` block is the authority on what each one means.
      def hadlock_variant(standard)
        variant = standard.to_s.delete_prefix('hadlock_1991_').to_sym
        Services::Growth::Hadlock1991.new(manifest: manifest_for(standard), variant: variant)
      end

      def manifest_for(standard) = manifests[MANIFEST_KEYS.fetch(standard, standard)]

      def table_chart(klass, standard, table)
        klass.new(manifest: manifest_for(standard), table: tables[table])
      end
    end
  end
end
