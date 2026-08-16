# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      # The data a growth chart is drawn from: centile curves across
      # gestation, and optionally the one point a reader came to look at.
      #
      # Nothing here is a new reading of a standard. Every gram on every
      # curve is what that standard's own Centiles service answers (see
      # Curves), and the plotted point is what its forward adapter answers;
      # this service composes the chart registry and arranges those answers
      # into a shape a caller can serialise.
      #
      # A point the chart refuses fails the whole call: a chart drawn without
      # the point that was asked for is indistinguishable from one nobody
      # asked a point of.
      class ChartSeries
        include Dry::Monads[:result]

        # Which reverse (weight-at-centile) service reads each manifest.
        CENTILES = { intergrowth21: Intergrowth::Centiles,
                     hadlock_1991: Hadlock1991::Centiles,
                     nichd: Nichd::Centiles,
                     who: Who::Centiles }.freeze

        COMBINED = :combined

        def initialize(manifests:, tables:)
          @manifests = manifests
          @tables = tables
          @charts = Charts.new(manifests: manifests, tables: tables).call
        end

        def call(standard:, centiles: nil, sex: nil, stratum: nil, step: nil, point: nil)
          entry = charts[standard]
          return unsupported(standard) unless entry

          refused = refuse_step(standard, entry, step)
          refused || draw(standard, entry, centiles: centiles, sex: sex, stratum: stratum,
                                           step: step, point: point)
        end

        private

        attr_reader :manifests, :tables, :charts

        # ----------------------------------------------------------- refusals

        def unsupported(standard)
          Failure([:unsupported_standard, { requested: standard, available: charts.keys }])
        end

        # A step is an instruction about where to evaluate a curve; a table
        # standard has only rows to read. On a computed curve a non-positive
        # step names no grid at all.
        def refuse_step(standard, entry, step)
          return nil unless step
          if table?(entry)
            return Failure([:invalid_input, { step: step, standard: base_of(standard),
                                              valid_for: :closed_form }])
          end
          return nil if step.positive?

          Failure([:invalid_input, { step: step, valid_range: [0, nil] }])
        end

        # ------------------------------------------------------------ drawing

        # NICHD with no stratum answers with the whole spread, one chart per
        # published stratum — race/ethnicity is never defaulted, and the
        # spread is the paper's own headline finding. A standard whose charts
        # include a combined one (WHO) is answered with that instead.
        def draw(standard, entry, **request)
          values = entry[:manifest][:stratification][:values].map(&:to_sym)
          if request[:stratum].nil? && !values.empty? && !values.include?(COMBINED)
            return spread(standard, entry, values, request)
          end

          single(standard, entry, request)
        end

        def spread(standard, entry, values, request)
          drawn = values.map { |value| single(standard, entry, request.merge(stratum: value)) }
          drawn.find(&:failure?) || Success(drawn.map(&:value!))
        end

        def single(standard, entry, request)
          curves = read_curves(standard, entry, request)
          return curves if curves.failure?

          plot(standard, entry, request).fmap do |plotted|
            assemble(standard: standard, entry: entry, request: request,
                     series: curves.value!, plotted: plotted)
          end
        end

        def read_curves(standard, entry, request)
          Curves.new(reverse: reverse_for(standard, entry), entry: entry,
                     sex: request[:sex], stratum: request[:stratum], step: request[:step])
                .call(request[:centiles] || published_centiles(entry[:manifest], request[:sex]))
        end

        def assemble(standard:, entry:, request:, series:, plotted:)
          Biometry::ChartSeries.new(
            chart: chart_block(standard, entry, request), source: source_block(entry),
            series: series, point: plotted,
            known_issues: entry[:manifest][:known_issues] || []
          )
        end

        def reverse_for(standard, entry)
          base = base_of(standard)
          klass = CENTILES.fetch(base)
          return klass.new(manifest: entry[:manifest], table: tables[base]) if table?(entry)
          if base == :hadlock_1991
            return klass.new(manifest: entry[:manifest],
                             variant: variant_of(standard, entry[:manifest]))
          end

          klass.new(manifest: entry[:manifest])
        end

        # The columns the standard itself publishes: sexed tables are
        # narrower than the combined one, and only the caller knows which
        # chart they are drawing.
        def published_centiles(manifest, sex)
          block = manifest[:centiles]
          return (sex ? block[:sex_specific] : block[:combined]) if block.key?(:combined)

          block[:tabulated] || block[:published]
        end

        def plot(standard, entry, request)
          Plot.new(adapter: entry[:adapter], base: base_of(standard),
                   sex: request[:sex], stratum: request[:stratum])
              .call(request[:point])
        end

        # ----------------------------------------------------- describing it

        def chart_block(standard, entry, request)
          manifest = entry[:manifest]
          { standard: standard, variant: variant_of(standard, manifest),
            stratum: stratum_read(entry, request),
            type: manifest.dig(:source, :type).to_sym, ga_units: manifest[:ga_units]&.to_sym,
            valid_ga_weeks: manifest[:valid_ga_weeks], basis: basis_of(entry) }
        end

        def source_block(entry)
          source = entry[:manifest][:source]
          { citation: source[:citation], doi: source[:doi], pmid: source[:pmid],
            type: source[:type].to_sym }
        end

        def variant_of(standard, manifest)
          manifest[:variants]&.find { |_, each| each[:id].to_sym == standard }&.first
        end

        # Which of the standard's charts the curves were read off: the named
        # stratum, the named sex, or the combined chart where one exists.
        def stratum_read(entry, request)
          return request[:stratum] if request[:stratum]
          return nil if entry[:manifest][:stratification][:values].empty?

          request[:sex] || COMBINED
        end

        def basis_of(entry) = table?(entry) ? :published_table : :closed_form

        def table?(entry) = entry[:manifest].dig(:source, :access).to_s == 'table'

        # Both Hadlock variants answer to the one manifest key; everything
        # else's chart id is its manifest key already.
        def base_of(standard) = manifests.key?(standard) ? standard : :hadlock_1991
      end
    end
  end
end
