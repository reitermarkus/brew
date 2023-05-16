# typed: true
# frozen_string_literal: true

require "forwardable"
require "uri"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's homepage ends with a slash
      # if it does not have a path component.
      class HomepageUrlTrailingSlash < Base
        include RangeHelp
        include IgnoredNode
        extend AutoCorrector

        MSG_NO_SLASH = "'%<url>s' must have a slash after the domain."

        URL_REGEX = begin
          uri_regex = URI::DEFAULT_PARSER.regexp[:URI_REF]
          Regexp.new("\\A#{uri_regex.source}\\Z", uri_regex.options)
        end.freeze

        def on_str(node)
          return if node.heredoc? || node.parent&.heredoc?
          return if node.parent&.regexp_type?
          return if ignored_node?(node)

          return unless applicable_to?(node)

          url = str_content_with_placeholders(node)
          return unless url

          begin
            uri = URI(url.encode("UTF-8", invalid: :replace, replace: "X").tr("�", "X"))
          rescue URI::InvalidURIError
            return
          end
          return unless ["http:", "https:"].include?(uri.scheme)
          return unless uri.host
          return if uri.path && !uri.path.empty?

          scheme = url[0..(uri.scheme.length + 2)]
          domain_length = uri.host.length + (uri.port&.to_s&.length || -1) + 1
          domain = url[(scheme.length)...(scheme.length + domain_length)]

          # Cannot reason about domains which end with interpolation.
          return if domain.end_with?("�")

          url_begin = if node.parent&.array_type? && node.parent&.percent_literal?(:string)
            node.source_range.begin.end_pos
          else
            contents_range(node).begin.end_pos
          end
          domain_range = range_between(url_begin, url_begin + scheme.length + domain.length)

          add_offense(domain_range, message: format(MSG_NO_SLASH, url: domain_range.source)) do |corrector|
            corrector.insert_after(domain_range, "/")
          end
        end
        alias on_dstr on_str

        private

        def applicable_to?(node)
          return false unless (parent = node.parent)

          return false unless parent.send_type?

          return [:head, :stable, :url, :homepage].include?(parent.method_name) if parent.inside_formula_block?

          return unless parent.inside_cask_block?

          [:url, :homepage].include?(parent.method_name)
        end

        # Get string content with interpolation replaced by the replacement character.
        def str_content_with_placeholders(node)
          if node.str_type?
            node.str_content
          elsif node.dstr_type?
            node.children.map do |child_node|
              ignore_node(child_node)
              str_content_with_placeholders(child_node)
            end.join
          else
            "�" * node.source.length
          end
        end
      end
    end
  end
end
