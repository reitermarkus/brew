# frozen_string_literal: true

describe Cachable do
  subject(:cachable) { Object.new.extend(described_class) }

  describe "#cache" do
    it "returns a Hash" do
      expect(cachable.cache).to be_a Hash
    end

    it "caches the block" do
      expect do
        3.times do
          cachable.cache(:cache_item) {
            puts "Hello, world!"
          }
        end
      end.to output("Hello, world!\n").to_stdout
    end
  end

  describe "#clear_cache" do
    it "clears the cache" do
      expect(cachable.cache).to be_empty
      cachable.cache[:cache_item] = 42
      expect(cachable.cache).not_to be_empty
      cachable.clear_cache
      expect(cachable.cache).to be_empty
    end
  end
end
