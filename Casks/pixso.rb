cask "pixso" do
  version "2.3.4"
  sha256 "8398bfe4d80ad56853d576ab7b1c41bb8b014da836950a08efc5fe0e2b14f778"

  url "https://pixso-pub-prod.obs.cn-east-3.myhuaweicloud.com/cms/download/package/app/bosyun/#{version}/Pixso_mac_v#{version.gsub(".", "_")}.dmg"
  name "Pixso"
  desc "Collaborative UI design tool"
  homepage "https://pixso.cn/"

  livecheck do
    skip "Versioned URL with no public version feed"
  end

  app "Pixso.app"
end
