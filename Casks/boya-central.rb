cask "boya-central" do
  version "1.1.1"
  sha256 "da435700b2b28b35a022d35ef0e30b24e5d95583782feb53e7b0eab6b5f0722b"

  url "https://oss.boyamic.com/app/BOYACentral-#{version}.pkg",
      verified: "oss.boyamic.com/app/"
  name "BOYA Central"
  desc "Desktop companion app for BOYA microphones"
  homepage "https://www.boyamic.com/"

  livecheck do
    skip "Versioned URL with no public version feed"
  end

  depends_on macos: ">= :monterey"  # Info.plist LSMinimumSystemVersion 12.4

  # pkg 内含两个子包：主程序 com.boyaCentral.BOYA.Appcn（BOYA Central.app）
  # 与 CoreAudio 驱动 com.boyaCentral.BOYA.Driver（BOYARouterDevice.driver）
  pkg "BOYACentral-#{version}.pkg"

  uninstall pkgutil: [
    "com.boyaCentral.BOYA.Appcn",
    "com.boyaCentral.BOYA.Driver",
  ]
end
