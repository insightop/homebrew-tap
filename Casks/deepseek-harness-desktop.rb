cask "dsh-desktop" do
  version "2.0.0"
  sha256 "d3f7f10acd90ea58ac0922428ab3d8a96ced8c73227b8c8f76f313181e8a0cfe"

  url "https://github.com/anywhere-labs/deepseek-harness-desktop/releases/download/v#{version}/DSH-Desktop-#{version}-arm64.dmg",
      verified: "github.com/anywhere-labs/deepseek-harness-desktop"
  name "Deepseek Harness Desktop"
  desc "Deepseek Harness Desktop developed by anywhere-labs."
  homepage "https://github.com/anywhere-labs/deepseek-harness-desktop"

  app "DSH Desktop.app"
end
