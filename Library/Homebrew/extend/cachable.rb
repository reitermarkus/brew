# typed: strict
# frozen_string_literal: true

module Cachable
  sig { params(key: Symbol, block: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
  def cache(key = T.unsafe(nil), &block)
    @cache ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))

    if key && block
      return @cache[key] if @cache.key?(key)

      @cache[key] = yield.freeze
    else
      @cache
    end
  end

  sig { void }
  def clear_cache
    cache.clear
  end
end
