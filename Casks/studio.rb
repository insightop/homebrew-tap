cask "studio" do
  version :latest
  sha256 :no_check

  url "https://vault.insightop.com/studio/darwin/?latest",
      verified: "vault.insightop.com/studio/darwin/"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"
end
