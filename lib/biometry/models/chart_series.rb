# frozen_string_literal: true

module Biometry
  # One growth chart, ready to draw: what was drawn (chart), where the numbers
  # came from (source), the centile curves (series), the plotted point when
  # one was asked for (nil otherwise), and the manifest's known issues
  # verbatim — defects are data a consumer must be able to show.
  ChartSeries = Data.define(:chart, :source, :series, :point, :known_issues) do
    # Data#to_h is shallow; a caller serialises this, so the curves convert
    # too and the result is plain hashes the whole way down.
    def to_h = super.merge(series: series.map(&:to_h))
  end
end
