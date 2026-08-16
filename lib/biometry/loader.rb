# frozen_string_literal: true

module Biometry
  # The one read of data/. Everything else in the library takes contents, not
  # paths; this is where the paths are, named once so the CLI and a web app
  # cannot drift on which files the library is built from.
  #
  # Raises rather than returning a Result: a manifest marked unverified is a
  # developer error caught at boot, not a runtime condition a caller branches
  # on.
  module Loader
    MANIFESTS = %i[acog_redating hadlock_1985 hadlock_1991 intergrowth21 nichd who].freeze
    TABLES = %i[nichd who].freeze

    def self.call(data_root: DATA_ROOT)
      manifests, dropped = read_manifests(data_root)
      Context.new(manifests: manifests, tables: read_tables(data_root), dropped: dropped)
    end

    def self.read_manifests(data_root)
      manifests = {}
      dropped = {}
      MANIFESTS.each do |name|
        manifests[name], dropped[name] = ReferenceData.load_manifest(data_root / "#{name}.yml")
      end
      [manifests, dropped]
    end
    private_class_method :read_manifests

    def self.read_tables(data_root)
      TABLES.to_h { |name| [name, ReferenceData.load_table(data_root / "percentiles/#{name}.csv")] }
    end
    private_class_method :read_tables
  end

  # The entry point for everything that is not the CLI: read data/ once,
  # return the wired Context. Shadows Kernel#load deliberately — nothing in
  # this library loads Ruby files by path.
  def self.load(data_root: DATA_ROOT)
    Loader.call(data_root: data_root)
  end
end
