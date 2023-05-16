# frozen_string_literal: true

require "rubocops/rubocop-cask"

describe RuboCop::Cop::Cask::HomepageUrlTrailingSlash, :config, :focus do
  it "accepts a homepage URL ending with a slash" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/'
      end
    CASK
  end

  it "accepts a homepage URL with a path" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/path'
      end
    CASK
  end

  it "reports an offense when the homepage URL does not end with a slash and has no path" do
    expect_offense <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh'
                  ^^^^^^^^^^^^^^^^^^^ 'https://foo.brew.sh' must have a slash after the domain.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/'
      end
    CASK
  end

  it "reports an offense when the homepage URL does not end with a slash and has a fragment" do
    expect_offense <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh#home'
                  ^^^^^^^^^^^^^^^^^^^ 'https://foo.brew.sh' must have a slash after the domain.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/#home'
      end
    CASK
  end

  it "reports an offense when the homepage URL does not end with a slash and has a query" do
    expect_offense <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh?home'
                  ^^^^^^^^^^^^^^^^^^^ 'https://foo.brew.sh' must have a slash after the domain.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/?home'
      end
    CASK
  end

  context "when using interpolation" do
    it "accepts interpolation at the end" do
      expect_no_offenses <<~'CASK'
        cask 'foo' do
          homepage "https://foo.brew.sh#{path}"
        end
      CASK
    end

    it "reports an offense when the homepage URL does not end with a slash and has no path" do
      expect_offense <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh"
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 'https://#{version.major}-foo.brew.sh' must have a slash after the domain.
        end
      CASK

      expect_correction <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh/"
        end
      CASK
    end

    it "reports an offense when the homepage URL does not end with a slash and has a fragment" do
      expect_offense <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh#home"
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 'https://#{version.major}-foo.brew.sh' must have a slash after the domain.
        end
      CASK

      expect_correction <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh/#home"
        end
      CASK
    end

    it "reports an offense when the homepage URL does not end with a slash and has a query" do
      expect_offense <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh?home"
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 'https://#{version.major}-foo.brew.sh' must have a slash after the domain.
        end
      CASK

      expect_correction <<~'CASK'
        cask 'foo' do
          homepage "https://#{version.major}-foo.brew.sh/?home"
        end
      CASK
    end
  end
end
