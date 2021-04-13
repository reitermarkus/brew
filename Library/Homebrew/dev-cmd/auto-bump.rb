# typed: false
# frozen_string_literal: true

require "cli/parser"
require "livecheck/livecheck"
require "cache_store"

module Homebrew
  extend T::Sig

  module_function

  sig { returns(CLI::Parser) }
  def auto_bump_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Create a pull request to update <cask> with a new version.
      EOS
      switch "-n", "--dry-run",
             description: "Print what would be done rather than doing it."
      switch "--write",
             description: "Make the expected file modifications without taking any Git actions."
      switch "--commit",
             depends_on:  "--write",
             description: "When passed with `--write`, generate a new commit after writing changes "\
                          "to the cask file."
      switch "--no-audit",
             description: "Don't run `brew audit` before opening the PR."
      switch "--online",
             description: "Run `brew audit --online` before opening the PR."
      switch "--no-style",
             description: "Don't run `brew style --fix` before opening the PR."
      switch "--no-browse",
             description: "Print the pull request URL instead of opening in a browser."
      switch "--no-fork",
             description: "Don't try to fork the repository."
      switch "-f", "--force",
             description: "Ignore duplicate open PRs."
      switch "--formula", "--formulae",
             description: "Treat all named arguments as formulae."
      switch "--cask", "--casks",
             description: "Treat all named arguments as casks."
      switch "--installed",
             description: "Check formulae/casks that are currently installed."

      conflicts "--dry-run", "--write"
      conflicts "--no-audit", "--online"
      conflicts "--formula", "--cask"

      named_args [:file, :tap, :formula, :cask], min: 1
    end
  end

  class AutoBumpCacheStore < CacheStore
    def update!(formula_or_cask, state)
      database.set(formula_or_cask.full_name, state)
    end

    def fetch(formula_or_cask)
      state = database.get(formula_or_cask.full_name)
      return unless state

      status, result = state
      status = status&.to_sym
      result = result&.deep_symbolize_keys

      if (valid_until = result&.fetch(:valid_until)&.yield_self { |t| Time.parse(t) }) && valid_until < Time.now
        delete!(formula_or_cask)
        return
      end

      [status, result]
    end

    def delete!(formula_or_cask)
      database.delete(formula_or_cask.full_name)
    end
  end

  def auto_bump
    args = auto_bump_args.parse

    formulae_and_casks = args.named.to_formulae_and_casks(recurse_tap: true).shuffle

    options = {
      json:      true,
      full_name: true,
      debug:     args.debug?,
      verbose:   args.verbose?,
    }.compact

    formulae_and_casks.each do |formula_or_cask|
      cached_result = CacheStoreDatabase.use(:auto_bump) do |db|
        AutoBumpCacheStore.new(db).fetch(formula_or_cask)
      end

      status, result = if cached_result
        cached_result
      else
        begin
          Livecheck.check_formula_or_cask(formula_or_cask, **options)
        rescue => e
          ofail e
          next
        end
      end

      cask = result[:cask]
      formula = result[:formula]

      print(cask || formula)

      if cached_result
        print " (from cache)"
      else
        CacheStoreDatabase.use(:auto_bump) do |db|
          result[:valid_until] = Time.now + 1.day
          AutoBumpCacheStore.new(db).update!(formula_or_cask, [status, result])
        end
      end

      case status
      when :success
        outdated = result.fetch(:version).fetch(:outdated)
        latest = result.fetch(:version).fetch(:latest)

        puts ": #{latest}"

        next unless outdated

        bump_args = []

        if cask
          bump_args << "bump-cask-pr"
          bump_args << formula_or_cask.sourcefile_path
        end

        if formula
          bump_args << "bump-formula-pr"
          bump_args << formula_or_cask.path
        end

        bump_args << "--version" << latest
        bump_args << "--no-audit" if args.no_audit?
        bump_args << "--dry-run" if args.dry_run?

        ohai ["brew", *bump_args].shelljoin
        system_command! HOMEBREW_BREW_FILE, args: bump_args, print_stdout: true, print_stderr: true
      else
        puts ": #{result[:messages]&.join(", ") || result[:status]} #{status.inspect}"
      end
    rescue => e
      $stderr.puts e.backtrace
      onoe e
    end
  end
end
