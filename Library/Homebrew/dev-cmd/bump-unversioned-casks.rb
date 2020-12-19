# typed: false
# frozen_string_literal: true

require "timeout"
require "cask/download"
require "cask/installer"
require "cask/cask_loader"
require "cli/parser"
require "tap"
require "unversioned_cask_checker"

module Homebrew
  extend T::Sig

  extend SystemCommand::Mixin

  sig { returns(CLI::Parser) }
  def self.bump_unversioned_casks_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Check all casks with unversioned URLs in a given <tap> for updates.
      EOS
      switch "-n", "--dry-run",
             description: "Do everything except caching state and opening pull requests."
      flag  "--limit=",
            description: "Maximum runtime in minutes."
      flag   "--state-file=",
             description: "File for caching state."

      named_args [:cask, :tap], min: 1
    end
  end

  sig { void }
  def self.bump_unversioned_casks
    Homebrew.install_bundler_gems!
    require "concurrent"

    args = bump_unversioned_casks_args.parse

    state_file = if args.state_file.present?
      Pathname(args.state_file).expand_path
    else
      HOMEBREW_CACHE/"bump_unversioned_casks.json"
    end
    state_file.dirname.mkpath

    state = state_file.exist? ? JSON.parse(state_file.read) : {}

    casks = args.named.to_paths(only: :cask, recurse_tap: true).map { |path| Cask::CaskLoader.load(path) }

    unversioned_casks = casks.select { |cask| cask.url&.unversioned? }

    ohai "Unversioned Casks: #{unversioned_casks.count} (#{state.size} cached)"

    checked, unchecked = unversioned_casks.partition { |c| state.key?(c.full_name) }

    limit = args.limit.presence&.to_f

    timeout = [*limit&.minutes, 5.minutes].min
    end_time = Concurrent::MVar.new(limit ? Time.now + limit.minutes : nil)

    queue =
      # Start with random casks which have not been checked.
      unchecked.shuffle +
      # Continue with previously checked casks, ordered by when they were last checked.
      checked.sort_by { |c| state.dig(c.full_name, "check_time") }

    state_file = Concurrent::MVar.new(state_file)

    check_pool = Concurrent::FixedThreadPool.new(4)
    futures = queue.map do |cask|
      [
        cask.token,
        Concurrent::Promises.future_on(check_pool, cask, end_time, timeout) do |cask, end_time, timeout|
          next if end_time.borrow { |t| t ? Time.now > t : false }

          key = cask.full_name

          new_state = bump_unversioned_cask(cask, state: state.fetch(key, {}), timeout: timeout)

          next [cask, new_state] if new_state.key?(:skip_reason)

          state_file.borrow do |file|
            state[key] = new_state
            file.atomic_write JSON.generate(state) unless args.dry_run?
          end

          [cask, new_state]
        end,
      ]
    end
    check_pool.shutdown

    sigint = Queue.new

    default_trap = trap("INT") do
      $stderr.puts "\nWaiting for running threads to finish..."
      sigint.enq true
      Homebrew.failed = true

      trap("INT") { raise Interrupt }
    end

    Concurrent::Promises.future do
      sigint.deq
      end_time.set! Time.at(0)
    end

    futures.each do |cask_token, future|
      cask, new_state = future.value

      if (exception = future.reason)
        puts "#{cask_token}: error -- #{exception}"
      elsif cask.nil?
        break
      elsif (skip_reason = new_state.delete(:skip_reason))
        puts "#{cask}: skipped -- #{skip_reason}"
      elsif (version = new_state[:version])
        if cask.version == version
          puts "#{cask}: #{version}"
        else
          puts "#{cask}: #{Formatter.error(cask.version)} --> #{Formatter.success(version)}"

          bump_cask_pr_args = [
            "bump-cask-pr",
            "--version", version.to_s,
            "--sha256", ":no_check",
            "--message", "Automatic update via `brew bump-unversioned-casks`.",
            cask.sourcefile_path
          ]

          if args.dry_run?
            bump_cask_pr_args << "--dry-run"
            # oh1 "Would bump #{cask} from #{cask.version} to #{version}"
          else
            # oh1 "Bumping #{cask} from #{cask.version} to #{version}"
          end

          # system_command! HOMEBREW_BREW_FILE, args: bump_cask_pr_args
        end
      else
        puts "#{cask}: could not determine version"
      end
    end

    check_pool.wait_for_termination
  end

  sig {
    params(cask: Cask::Cask, state: T::Hash[String, T.untyped], timeout: T.nilable(Number))
      .returns(T.nilable(T::Hash[String, T.untyped]))
  }
  def self.bump_unversioned_cask(cask, state:, timeout:)
    end_time = end_time!(timeout)

    unversioned_cask_checker = UnversionedCaskChecker.new(cask)

    new_state = {}

    if !unversioned_cask_checker.single_app_cask? && !unversioned_cask_checker.single_pkg_cask?
      return { skip_reason: "not a single-app or PKG cask" }
    end

    last_check_time = state["check_time"]&.yield_self { |t| Time.parse(t) }

    check_time = Time.now
    new_state[:check_time] = check_time&.iso8601
    if last_check_time && check_time < (last_check_time + 1.day)
      return { skip_reason: "already checked within the last 24 hours" }
    end

    last_sha256 = state["sha256"]
    last_time = state["time"]&.yield_self { |t| Time.parse(t) }
    last_file_size = state["file_size"]

    download = Cask::Download.new(cask)

    time, file_size = download.time_file_size(timeout: timeout_from_end_time!(end_time))
    new_state[:time] = time&.iso8601
    new_state[:file_size] = file_size

    if last_time != time || last_file_size != file_size
      sha256 = unversioned_cask_checker.installer.download(quiet:   true,
                                                           timeout: timeout_from_end_time!(end_time)).sha256
      new_state[:sha256] = sha256

      if sha256.present? && last_sha256 != sha256
        version = unversioned_cask_checker.guess_cask_version(timeout: timeout_from_end_time!(end_time))
        new_state[:version] = version
      end
    end

    new_state
  end

  def self.end_time!(timeout)
    return if timeout.nil?

    raise Timeout::Error if timeout <= 0

    Time.now + timeout
  end

  def self.timeout_from_end_time!(end_time)
    return if end_time.nil?

    timeout = end_time - Time.now

    raise Timeout::Error if timeout <= 0

    timeout
  end
end
