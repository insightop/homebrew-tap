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

  # 未公证 App：上游只有 Developer ID 签名、未做 Apple 公证（1.0.4 与 1.2.0 均如此，
  # 非某个版本引入）。Homebrew 下载后会打上 com.apple.quarantine，首次启动时
  # Gatekeeper 弹「无法验证开发者」。这里在安装后移除该属性，避免弹窗。
  #
  # 说明：移除 quarantine 只是跳过后加的隔离标记，**不影响签名完整性校验**
  # （xattr 与代码签名无关，codesign --verify 仍通过）。这是本 tap 中自研 App
  # （studio）既有的做法。
  # {{appdir}} 会自动适配每台电脑的安装目录（默认 /Applications，
  # 可用 HOMEBREW_CASK_OPTS="--appdir=..." 覆盖）。
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/闲鱼卖家客服.app"],
        sudo: false
  end

  zap trash: "~/Library/Application Support/xianyu-seller-im"
end
