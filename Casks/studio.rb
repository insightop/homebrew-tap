cask "studio" do
  version ""
  sha256 "73a28cd4074fa8073d20d611d42f89f027628306e35297b434fb2e2ee8fa630d"
  bundle_id "com.insightop.studio"

  url "https://vault.insightop.com/studio/darwin/Studio--arm64.dmg",
      verified: "vault.insightop.com/studio/darwin/"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"
end
