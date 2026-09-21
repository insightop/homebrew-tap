cask "dsh-desktop" do
  version "2.0.13"
  sha256 "14dca10647c5f0ccf39433239134995998ab7b5d34aa179570b8fac0b8569363"

  # 资产命名在 v2.0.0 → v2.0.1 间变过一次（旧：DSH-Desktop-<v>-arm64.dmg），
  # v2.0.1 起稳定为 universal 包，故用新形态。仓库也已由 deepseek-harness-desktop
  # 更名为 dsh-desktop（旧名仍重定向）。
  url "https://github.com/anywhere-labs/dsh-desktop/releases/download/v#{version}/DSH.Desktop-#{version}-universal.dmg"
  name "Deepseek Harness Desktop"
  desc "Deepseek Harness Desktop developed by anywhere-labs."
  homepage "https://github.com/anywhere-labs/dsh-desktop"

  # 上游同时发布正式版与 *-beta.1 预发布版（如 v2.0.13 与 v2.0.13-beta.1）。
  # :github_latest 读 /releases/latest，天然排除 prerelease，避免把 beta 当成新版本。
  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  depends_on macos: :monterey  # Info.plist LSMinimumSystemVersion 12.0

  app "DSH Desktop.app"
end
