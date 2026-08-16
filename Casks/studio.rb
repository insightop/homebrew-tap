cask "studio" do
  version "0.1.0-ff8af8d"
  sha256 "988bbb7018c8fb4593b9c3568d76395f5ba1b5e06db41c13b986f86627246780"

  url "https://vault.insightop.com/studio/darwin/Studio-0.1.0-ff8af8d-arm64.dmg",
      verified: "vault.insightop.com/studio/darwin/"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"
end
