# frozen_string_literal: true

module Biometry
  # What a consumer holds after data/ has been read once: the loaded reference
  # data and the services wired on it. Built by Biometry.load; a web process
  # keeps one for its lifetime and shares it across threads, which is safe
  # because everything reachable from it is frozen.
  #
  # No clinical behaviour is decided here — every method hands the question to
  # the service that owns it.
  class Context
    attr_reader :manifests, :tables, :dropped, :charts, :catalog

    def initialize(manifests:, tables:, dropped:)
      @manifests = manifests.freeze
      @tables = tables.freeze
      @dropped = dropped.freeze
      @charts = Services::Growth::Charts.new(manifests: manifests, tables: tables).call
      @catalog = Services::Catalog.new(manifests: manifests).call
      @dating = Services::Dating::AllDerivations.new
      @weights = Services::Weight::AllFormulas.new(hadlock: manifests[:hadlock_1985],
                                                   intergrowth: manifests[:intergrowth21])
      freeze
    end

    def dating(**request) = @dating.call(**request)

    def weights(scan) = @weights.call(scan)
  end
end
