cask "mimo-desktop" do
  version "26.922.220226"
  sha256 "fbe46713f40bd3f49a736bc3e0627365545ad6e33d8b09a26631ce8b48cca74c"

  # 官方同时提供固定 URL（XiaomiMiMo-latest-arm64.dmg）与版本化 URL；
  # 用版本化 URL，以便 sha256 固定校验与版本追踪。版本号形如 26.922.220226。
  url "https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-#{version}-arm64.dmg"
  name "Xiaomi MiMo"
  desc "Desktop AI agent from Xiaomi (MiMo Code)"
  homepage "https://app.xiaomimimo.com/download"

  # 官方发布 manifest 为结构化 JSON，含 mac-arm64 的版本、下载地址与官方 sha256，
  # 是比页面抓取更可靠的版本源。用 Json 策略直接取该字段。
  livecheck do
    url "https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/manifest.json"
    strategy :json do |json|
      json.dig("platforms", "mac-arm64", "version")
    end
  end

  depends_on arch: :arm64  # 上游只提供 mac-arm64，无 Intel 版
  depends_on macos: :monterey  # Info.plist LSMinimumSystemVersion 12.0

  app "Xiaomi MiMo.app"

  # 名称取自 app.asar 内 package.json 的 name（Electron 的 userData 目录名）
  # 与 app-update.yml 的 updaterCacheDirName，非猜测。
  zap trash: [
    "~/Library/Application Support/xiaomi-mimo-desktop",
    "~/Library/Caches/xiaomi-mimo-desktop-updater",
    "~/Library/Preferences/com.xiaomi.mimo.desktop.plist",
  ]
end
