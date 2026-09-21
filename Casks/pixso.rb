cask "pixso" do
  version "2.3.1"
  sha256 "d7429f7f608c9e8ebcc6bbb9477dd91c701a7418451bd40132516ed61e8b41bb"

  url "https://pixso-pub-prod.obs.cn-east-3.myhuaweicloud.com/cms/download/package/app/bosyun/#{version}/Pixso_mac_v#{version.gsub(".", "_")}.dmg"
  name "Pixso"
  desc "Collaborative UI design tool"
  homepage "https://pixso.cn/"

  livecheck do
    skip "Versioned URL with no public version feed"
  end

  app "Pixso.app"
end
