cask "studio" do
  version "0.1.0-e89e7df"
  sha256 "fd66e234d9de149f781b22a0ed0a5d393c5d1b8df3a86e58cb5fcddeb01fa835"

  url "https://vault.insightop.com/studio/darwin/Studio-0.1.0-e89e7df-arm64.dmg",
      verified: "vault.insightop.com/studio/darwin/"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"
end
