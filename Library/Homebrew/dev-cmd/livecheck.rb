# frozen_string_literal: true

require "cli/parser"
require "formula"
require "livecheck/livecheck"
require "livecheck/strategy"

module Homebrew
  module_function

  WATCHLIST_PATH = (
    ENV["HOMEBREW_LIVECHECK_WATCHLIST"] ||
    "#{Dir.home}/.brew_livecheck_watchlist"
  ).freeze

  def livecheck_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `livecheck` [<formulae>|<casks>]

        Check for newer versions of formulae and/or casks from upstream.

        If no formula or cask argument is passed, the list of formulae and casks to check is taken from
        `HOMEBREW_LIVECHECK_WATCHLIST` or `~/.brew_livecheck_watchlist`.
      EOS
      switch "--full-name",
             description: "Print formulae/casks with fully-qualified names."
      flag   "--tap=",
             description: "Check the formulae/casks within the given tap, specified as <user>`/`<repo>."
      switch "--installed",
             description: "Check formulae/casks that are currently installed."
      switch "--json",
             description: "Output informations in JSON format."
      switch "--all",
             description: "Check all available formulae/casks."
      switch "--newer-only",
             description: "Show the latest version only if it's newer than the formula/cask."
      conflicts "--debug", "--json"
      conflicts "--tap=", "--all", "--installed"
    end
  end

  def livecheck
    args = livecheck_args.parse

    if args.debug? && args.verbose?
      puts args
      puts ENV["HOMEBREW_LIVECHECK_WATCHLIST"] if ENV["HOMEBREW_LIVECHECK_WATCHLIST"].present?
    end

    formulae_and_casks_to_check = if args.tap
      tap = Tap.fetch(args.tap)
      formulae = tap.formula_names.map { |name| Formula[name] }
      casks = tap.cask_tokens.map { |token| Cask::CaskLoader.load(token) }
      formulae + casks
    elsif args.installed?
      Formula.installed + Cask::Caskroom.casks
    elsif args.all?
      Formula.to_a + Cask::Cask.to_a
    elsif args.named.present?
      args.named.to_formulae_and_casks
    elsif File.exist?(WATCHLIST_PATH)
      begin
        names = Pathname.new(WATCHLIST_PATH).read.lines
                        .reject { |line| line.start_with?("#") || line.blank? }
                        .map(&:strip)
        CLI::NamedArgs.new(*names).to_formulae_and_casks
      rescue Errno::ENOENT => e
        onoe e
      end
    end.sort_by do |formula_or_cask|
      formula_or_cask.respond_to?("token") ? formula_or_cask.token : formula_or_cask.name
    end

    raise UsageError, "No formulae or casks to check." if formulae_and_casks_to_check.blank?

    Livecheck.run_checks(formulae_and_casks_to_check, args)
  end
end
