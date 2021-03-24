class AbstractDownloadStrategy
  class << self
    def method_added(method)
      if method == :fetch && instance_method(method).arity == 0
        odeprecated "`def fetch` in a subclass of #{self}", "`def fetch(timeout: nil, **options)` and output a warning when `options` contains new unhandled options"

        class_eval do
          alias old_fetch fetch
          def fetch(timeout: nil)
            old_fetch
          end
        end
      end
    end
  end
end
