describe Tty do
  describe "::strip_ansi" do
    it "removes ANSI escape codes from a string" do
      expect(subject.strip_ansi("\033\[36;7mhello\033\[0m")).to eq("hello")
    end
  end

  describe "::width" do
    it "returns an Integer" do
      expect(subject.width).to be_kind_of(Integer)
    end

    it "cannot be negative" do
      expect(subject.width).to be >= 0
    end
  end

  context "when $stdout is not a TTY" do
    before do
      allow($stdout).to receive(:tty?).and_return(false)
    end

    it "returns an empty string for all colors" do
      expect(subject.to_s).to eq("")
      expect(subject.red.to_s).to eq("")
      expect(subject.green.to_s).to eq("")
      expect(subject.yellow.to_s).to eq("")
      expect(subject.blue.to_s).to eq("")
      expect(subject.magenta.to_s).to eq("")
      expect(subject.cyan.to_s).to eq("")
      expect(subject.default.to_s).to eq("")
    end
  end

  context "when $stdout is a TTY" do
    before do
      allow($stdout).to receive(:tty?).and_return(true)
    end

    it "returns ANSI escape codes for colors" do
      expect(subject.to_s).to eq("")
      expect(subject.red.to_s).to eq("\033[31m")
      expect(subject.green.to_s).to eq("\033[32m")
      expect(subject.yellow.to_s).to eq("\033[33m")
      expect(subject.blue.to_s).to eq("\033[34m")
      expect(subject.magenta.to_s).to eq("\033[35m")
      expect(subject.cyan.to_s).to eq("\033[36m")
      expect(subject.default.to_s).to eq("\033[39m")
    end

    it "returns an empty string for all colors when HOMEBREW_NO_COLOR is set" do
      ENV["HOMEBREW_NO_COLOR"] = "1"
      expect(subject.to_s).to eq("")
      expect(subject.red.to_s).to eq("")
      expect(subject.green.to_s).to eq("")
      expect(subject.yellow.to_s).to eq("")
      expect(subject.blue.to_s).to eq("")
      expect(subject.magenta.to_s).to eq("")
      expect(subject.cyan.to_s).to eq("")
      expect(subject.default.to_s).to eq("")
    end
  end
end
