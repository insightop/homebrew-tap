cask "pixso" do
  version "2.3.3"
  sha256 "783f321472eac943c80bdefbe5cf43239c63c3c55643891717ac78eed3feef9b"

  url "https://pixso-pub-prod.obs.cn-east-3.myhuaweicloud.com/cms/download/package/app/bosyun/#{version}/Pixso_mac_v#{version.gsub(".", "_")}.dmg"
  name "Pixso"
  desc "Collaborative UI design tool"
  homepage "https://pixso.cn/"

  livecheck do
    skip "Versioned URL with no public version feed"
  end

  app "Pixso.app"
end
