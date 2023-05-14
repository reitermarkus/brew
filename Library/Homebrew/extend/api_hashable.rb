# typed: true
# frozen_string_literal: true

# Used to substitute common paths with generic placeholders when generating JSON for the API.
module APIHashable
  def generating_hash!
    return if generating_hash?

    # Apply monkeypatches for API generation
    @old_home = Dir.home

    @old_homebrew_prefix = Thread.current[:HOMEBREW_PREFIX]
    Thread.current[:HOMEBREW_PREFIX] = Pathname.new(HOMEBREW_PREFIX_PLACEHOLDER)

    ENV["HOME"] = HOMEBREW_HOME_PLACEHOLDER

    @generating_hash = true
  end

  def generated_hash!
    return unless generating_hash?

    # Revert monkeypatches for API generation
    Thread.current[:HOMEBREW_PREFIX] = @old_homebrew_prefix

    ENV["HOME"] = @old_home

    @generating_hash = false
  end

  def generating_hash?
    @generating_hash ||= false
    @generating_hash == true
  end
end
