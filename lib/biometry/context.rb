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
      wire
      freeze
    end

    def dating(**request) = @dating.call(**request)

    def weights(scan) = @weights.call(scan)

    def report(**request) = @builder.call(**request)

    private

    # Every service is built once, before the freeze: a Context outlives a
    # request and is shared across threads, so nothing may be wired lazily.
    def wire
      @charts = Services::Growth::Charts.new(manifests: manifests, tables: tables).call
      @catalog = Services::Catalog.new(manifests: manifests).call
      @dating = Services::Dating::AllDerivations.new
      @weights = weight_service
      @builder = Services::Report::Builder.new(manifests: manifests, tables: tables)
    end

    def weight_service
      Services::Weight::AllFormulas.new(hadlock: manifests[:hadlock_1985],
                                        intergrowth: manifests[:intergrowth21])
    end
  end
end
