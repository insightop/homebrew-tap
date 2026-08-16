cask "studio" do
  version "0.1.0-a1b2c3d"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://vault.insightop.com/studio/darwin/Studio-#{version}-arm64.dmg",
      verified: "vault.insightop.com/studio/darwin/"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"
end
