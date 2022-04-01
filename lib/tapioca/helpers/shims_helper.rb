# typed: strict
# frozen_string_literal: true

module Tapioca
  module ShimsHelper
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Thor::Shell }

    SORBET_PAYLOAD_URL = "https://github.com/sorbet/sorbet/tree/master/rbi"

    sig { params(index: RBI::Index, dir: String).void }
    def index_payload(index, dir)
      return unless Dir.exist?(dir)

      say("Loading Sorbet payload... ")
      files = Dir.glob("#{dir}/**/*.rbi").sort
      parse_and_index_files(index, files)
      say(" Done", :green)
    end

    sig { params(index: RBI::Index, kind: String, dir: String).void }
    def index_rbis(index, kind, dir)
      return unless Dir.exist?(dir) && !Dir.empty?(dir)

      say("Loading #{kind} RBIs from #{dir}... ")
      files = Dir.glob("#{dir}/**/*.rbi").sort
      parse_and_index_files(index, files)
      say(" Done", :green)
    end

    sig { params(index: RBI::Index, shim_rbi_dir: String).returns(T::Hash[String, T::Array[RBI::Node]]) }
    def duplicated_nodes_from_index(index, shim_rbi_dir)
      duplicates = {}
      say("Looking for duplicates... ")
      index.keys.each do |key|
        nodes = index[key]
        next unless shims_have_duplicates?(nodes, shim_rbi_dir)

        duplicates[key] = nodes
      end
      say(" Done", :green)
      duplicates
    end

    sig { params(loc: RBI::Loc, path_prefix: String).returns(String) }
    def location_to_payload_url(loc, path_prefix:)
      url = loc.file || ""
      return loc.to_s unless url.start_with?(path_prefix)

      url = url.sub(path_prefix, SORBET_PAYLOAD_URL)
      url = "#{url}#L#{loc.begin_line}"
      url
    end

    private

    sig { params(index: RBI::Index, files: T::Array[String]).void }
    def parse_and_index_files(index, files)
      trees = files.map do |file|
        RBI::Parser.parse_file(file)
      rescue RBI::ParseError => e
        say_error("\nWarning: #{e} (#{e.location})", :yellow)
      end.compact
      index.visit_all(trees)
    end

    sig { params(nodes: T::Array[RBI::Node], shim_rbi_dir: String).returns(T::Boolean) }
    def shims_have_duplicates?(nodes, shim_rbi_dir)
      return false if nodes.size == 1

      shims = extract_shims(nodes, shim_rbi_dir)
      return false if shims.empty?

      props = extract_methods_and_attrs(shims)
      return false if props.empty?

      shims_with_sigs = extract_nodes_with_sigs(props)
      shims_with_sigs.each do |shim|
        shim_sigs = shim.sigs

        extract_methods_and_attrs(nodes).each do |node|
          next if node == shim
          return true if shim_sigs.all? { |sig| node.sigs.include?(sig) }
        end

        return false
      end

      true
    end

    sig { params(nodes: T::Array[RBI::Node], shim_rbi_dir: String).returns(T::Array[RBI::Node]) }
    def extract_shims(nodes, shim_rbi_dir)
      nodes.select do |node|
        node.loc&.file&.start_with?(shim_rbi_dir)
      end
    end

    sig { params(nodes: T::Array[RBI::Node]).returns(T::Array[T.any(RBI::Method, RBI::Attr)]) }
    def extract_methods_and_attrs(nodes)
      T.cast(nodes.select do |node|
        node.is_a?(RBI::Method) || node.is_a?(RBI::Attr)
      end, T::Array[T.any(RBI::Method, RBI::Attr)])
    end

    sig { params(nodes: T::Array[T.any(RBI::Method, RBI::Attr)]).returns(T::Array[T.any(RBI::Method, RBI::Attr)]) }
    def extract_nodes_with_sigs(nodes)
      nodes.reject { |node| node.sigs.empty? }
    end
  end
end
