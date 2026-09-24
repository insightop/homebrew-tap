cask "deepseek-harness" do
  version "0.1.7-rc.2"
  sha256 "30909618ec09559448fc5bb28dffd7111c66e30f9b2142165fb9a812896f6607"

  url "https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-#{version}-mac-arm64.dmg"
  name "DeepSeek Harness"
  desc "DeepSeek Harness desktop client"
  homepage "https://download.deepseek.com/"

  # 官方仅提供带版本号的直链，没有 latest 固定链接，也没有版本清单接口，
  # 因此没有可用的 livecheck 数据源。当前为 RC 预发布阶段，版本靠人工跟进。
  livecheck do
    skip "Versioned URL only; no public version feed"
  end

  depends_on macos: :ventura  # Info.plist LSMinimumSystemVersion 13.0
  depends_on arch: :arm64     # 官方仅提供 mac-arm64 包（无 x64 / universal）

  app "DeepSeek Harness.app"
end
