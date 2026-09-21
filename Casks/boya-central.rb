cask "boya-central" do
  version "1.2.4"
  sha256 "087fbf88f3f9741be8f574ad3a647ae6f5602753f85fcb23f04ea47a8ccb9e07"

  url "https://oss.boyamic.com/app/BOYACentral-#{version}.pkg"
  name "BOYA Central"
  desc "Desktop companion app for BOYA microphones"
  homepage "https://www.boyamic.com/"

  # 官网下载页为服务端渲染，直出 https://oss.boyamic.com/app/BOYACentral-<version>.pkg
  # （中文/英文/德文页一致，无需 JS、无需鉴权）。桌面端自身无可用更新接口（Qt 应用，
  # 内置 checkUpdateApp 已被上游注释掉），故以官网下载页为版本源。
  livecheck do
    url "https://www.boyamic.com/support/download"
    regex(/BOYACentral[._-]v?(\d+(?:\.\d+)+)\.pkg/i)
  end

  depends_on macos: :monterey  # Info.plist LSMinimumSystemVersion 12.4

  pkg "BOYACentral-#{version}.pkg"

  # pkg 内含两个子包：主程序 BOYA Central.app 与 CoreAudio 驱动。
  #
  # ⚠️ 上游标识会随大版本漂移（真实发生过一次），升级时务必核对：
  #   1.1.x → com.boyaCentral.BOYA.Appcn       + com.boyaCentral.BOYA.Driver（BOYARouterDevice.driver）
  #   1.2.4 → com.ccncv.boya.central           + com.jiayz.virtualaudiodriver（JIAYZVirtualAudioDriver.driver）
  # 下面的 pkgutil 列表必须与实际安装的 pkg 标识一致，否则 uninstall 会静默失效。
  # scripts/update-boya.rb 会在升级时自动改写此列表，并在 PR 描述中提示。
  uninstall pkgutil: [
    "com.ccncv.boya.central",
    "com.jiayz.virtualaudiodriver",
  ]
end
