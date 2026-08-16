cask "xianyu-seller-im" do
  version "1.0.4"
  sha256 "622efa8e10384aadcb7c6965e0b018359a194d48f476f5ed7b44df0bba4d826d"

  url "https://mtl.cn-hangzhou.oss.aliyun-inc.com/xianyu/seller/commonpro/xianyu-seller-im-#{version}-mac.dmg",
      verified: "mtl.cn-hangzhou.oss.aliyun-inc.com/xianyu/seller/"
  name "闲鱼卖家客服"
  name "Xianyu Seller IM"
  desc "Customer service tool for Xianyu (Goofish) sellers"
  homepage "https://seller.goofish.com/"

  livecheck do
    skip "Versioned URL with no public version feed"
  end

  depends_on arch: :arm64

  app "闲鱼卖家客服.app"

  zap trash: "~/Library/Application Support/xianyu-seller-im"
end
