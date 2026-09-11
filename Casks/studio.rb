cask "studio" do
  version :latest
  sha256 :no_check

  url "https://vault.insightop.com/studio/darwin/?latest"
  name "Studio"
  desc "Studio 桌面端（Electron 薄壳：多标签加载远程实例）"
  homepage "https://github.com/insightop/studio"

  app "Studio.app"

  # 未公证 App：安装后移除 quarantine 属性，避免 Gatekeeper 弹"无法验证"警告。
  # {{appdir}} 会自动适配每台电脑不同的安装目录（默认 /Applications，
  # 可用 HOMEBREW_CASK_OPTS="--appdir=..." 覆盖）。
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/Studio.app"],
        sudo: false
  end
end
