cask "xianyu-seller-im" do
  version "1.2.0"
  sha256 "3c16fdc3391f9f90a0ec3364b913e04cbe15d7854c35007f658bd2c739b66132"

  url "https://mtl.cn-hangzhou.oss.aliyun-inc.com/xianyu/seller/commonpro/xianyu-seller-im-#{version}-mac.dmg"
  name "闲鱼卖家客服"
  name "Xianyu Seller IM"
  desc "Customer service tool for Xianyu (Goofish) sellers"
  homepage "https://seller.goofish.com/"

  # 官方无版本清单/接口（Electron 无 feed、OSS 不可列目录），livecheck 无法可靠探测：
  # 卖家工作台 SPA 里写死的下载链接常年滞后（如 1.2.0 发布后仍指向 1.0.4），拿它当版本源会误判。
  # 版本探测由 .github/workflows/update-casks.yml 调用 scripts/update-xianyu.rb 完成（OSS 文件名窗口扫描）。
  livecheck do
    skip "No version feed; checked by scripts/update-xianyu.rb"
  end

  depends_on arch: :arm64

  app "闲鱼卖家客服.app"

  zap trash: "~/Library/Application Support/xianyu-seller-im"
end
