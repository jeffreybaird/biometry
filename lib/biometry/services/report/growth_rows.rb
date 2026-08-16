# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Report
      # Builds one row per chart reading.
      #
      # Formula and chart are paired, so each standard is read from the weight
      # its own manifest names — three distinct EFW values across four
      # standards, not one weight compared four ways. The pairing itself is
      # derived from the manifests by Growth::Charts.
      #
      # A chart that could not be read keeps its row and carries the Failure. A
      # silently short table looks complete when it is not, which is the same
      # reason the services refuse rather than skip.
      class GrowthRows
        include Dry::Monads[:result]

        # Display order only: what the registry serves is the manifests'
        # business, the order rows print in is this report's. Hadlock 1991
        # appears twice because its dispersion is contested (12.7% in the
        # abstract, 13.3% implied by Table 1; see the manifest's
        # `dispersion_contested` known_issue) and this library reports both
        # sides of a live dispute rather than picking one. `fetch` below makes
        # a chart this list names but the manifests no longer serve a loud
        # failure, not a silently missing row.
        ORDER = %i[intergrowth21 hadlock_1991_equation hadlock_1991_table who nichd].freeze

        def initialize(manifests:, tables:)
          @manifests = manifests
          @tables = tables
          @charts = Growth::Charts.new(manifests: manifests, tables: tables).call
        end

        def call(scan:, ga:, sex: nil, stratum: nil)
          weights = weigh(scan)
          ORDER.flat_map do |id|
            chart = charts.fetch(id)
            rows(id, chart, weights[chart[:formula]], ga: ga, sex: sex, stratum: stratum)
          end
        end

        private

        attr_reader :manifests, :tables, :charts

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
        def rows(id, chart, weight, **query)
          report = weight.success? ? read(id, chart[:adapter], weight.value!, **query) : weight
          row = { standard: id, weight: weight, report: report,
                  citation: chart[:manifest].dig(:source, :citation) }
          return [row] unless id == :nichd && report.success?

          report.value!.map { |percentile| row.merge(report: Success(percentile)) }
        end

        def read(id, adapter, estimate, ga:, sex:, stratum:)
          case id
          when :who then adapter.call(estimate: estimate, ga: ga, sex: sex)
          when :nichd then adapter.call(estimate: estimate, ga: ga, stratum: stratum)
          else adapter.call(estimate: estimate, ga: ga)
          end
        end
      end
    end
  end
end
