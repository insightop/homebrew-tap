# insightop/homebrew-tap

Insightop 组织自有 Homebrew tap，分发多个桌面应用的安装包（cask）。

## 安装

```bash
brew tap insightop/tap
brew install studio xianyu-seller-im boya-central dsh-desktop pixso
```

## 更新

```bash
# latest 模式（studio：cask 固定，--greedy 强制重拉最新）
brew upgrade --cask --greedy studio

# 固定版本模式（xianyu-seller-im、boya-central、dsh-desktop、pixso 等：普通升级语义）
brew upgrade --cask xianyu-seller-im boya-central dsh-desktop pixso
```

## 结构约定（多项目共用）

```
Casks/
├── studio.rb            # Studio 桌面端（macOS arm64，latest 模式：version :latest + sha256 :no_check + 固定 ?latest URL）
├── xianyu-seller-im.rb  # 闲鱼卖家客服（第三方官方 App，固定版本，自动检测：OSS 文件名探测）
├── boya-central.rb      # BOYA Central（博雅麦克风桌面端，pkg 安装器含驱动，自动检测：官网页面）
├── dsh-desktop.rb       # DSH Desktop（DeepSeek 桌面端，GitHub Releases，自动检测：/releases/latest）
├── pixso.rb             # Pixso（博思云创协同设计，官方 homebrew-cask 暂无，自动检测：官方更新通道）
└── <未来项目>.rb         # 每项目一个 cask 文件

scripts/
├── lib/cask_update.rb   # 共享库：7-Zip 定位/版本校验、plist 解析、dmg 内版本、cask 改写
└── update-<cask>.rb     # 每个 cask 一个探测脚本（pixso / dsh / xianyu / boya）

.github/
├── actions/render-cask/        # 共享 cask 渲染 action（固定版本模式的项目复用）
└── workflows/
    ├── update-casks.yml        # 统一入口：四个 cask 各一个 job
    └── update-cask.yml         # 可复用工作流：单个 cask 的检测 → 开 PR
```

- **自有项目（latest 模式）**：如 studio——cask 固定指向 vault 的 `?latest` 端点（vault 302 到最新 dmg），`version :latest` + `sha256 :no_check`，**tap 永不随发布更新**，各项目 CI 只需构建 + 上传 R2
- **自有项目（固定版本模式）**：可在 CI 中用共享 render-cask action 更新 cask 的 version/sha256/url（见下）
- **第三方官方 App**（如 xianyu-seller-im、boya-central、pixso、dsh-desktop）：无法自行构建，cask 指向官方下载源（sha256 固定校验）。**已接入自动检测**（见下节），由定时任务开 PR、人工合并

## 未公证 App 的 Gatekeeper 处理

Homebrew 下载安装包后会打上 `com.apple.quarantine` 隔离标记。若上游只做了 Developer ID 签名、**未做 Apple 公证**，首次启动会被 Gatekeeper 拦下并弹「无法验证开发者」。

本 tap 对这类 App 在 cask 里用 `postflight_steps` 清掉该标记（安装后执行）：

```ruby
app "Xxx.app"

postflight_steps do
  run "/usr/bin/xattr",
      args: ["-dr", "com.apple.quarantine", "{{appdir}}/Xxx.app"],
      sudo: false
end
```

`{{appdir}}` 由 Homebrew 在安装时展开（默认 `/Applications`，可用 `HOMEBREW_CASK_OPTS="--appdir=..."` 覆盖），因此中文/带空格的 App 名同样适用。

**判定某个 cask 是否需要它**（`Notarized` 则不需要）：

```bash
brew install --cask <token>          # 或挂载上游 dmg 后对 .app 执行：
spctl -a -vvv -t exec /Applications/Xxx.app
# accepted                    → 已公证，无需处理
# rejected / Unnotarized      → 未公证，需加 postflight_steps
```

当前状态：

| cask | 上游公证 | 处理 |
| --- | --- | --- |
| `studio` | 未公证 | 已有 `postflight_steps` |
| `xianyu-seller-im` | 未公证 | 已有 `postflight_steps` |
| `dsh-desktop` | 已公证 | 不需要 |
| `boya-central` | 已公证（pkg） | 不需要 |
| `pixso` | 已公证 | 不需要 |

> 清 quarantine 只去掉下载来源的隔离标记，**不影响代码签名校验**（`codesign --verify` 仍通过）；它解决的是「未公证导致的首次启动弹窗」，不是绕过签名验证。

## 自动检测新版本

第三方 App 没有发布钩子，因此用定时任务每天探测上游并开 PR（`main` 仍由人工合并，不做自动推送）。

**统一入口**：`.github/workflows/update-casks.yml`（每天 04:00 UTC / 北京时间 12:00）。
每个 cask 是一个**独立 job**（非 matrix），单个失败不影响其它、可单独重跑；手动触发时可只跑其中一个。
探测逻辑抽在可复用的 `.github/workflows/update-cask.yml` 里，四个 job 只声明各自差异。

| cask | 版本来源 | 检测方式 | runner |
| --- | --- | --- | --- |
| `pixso` | 官方 electron-updater 通道 `api.pixso.cn/.../latest-mac.yml` | 结构化 YAML + 官方 sha512 校验 | ubuntu |
| `dsh-desktop` | GitHub Releases 的 `/releases/latest` | `livecheck`（`:github_latest`）+ `scripts/update-dsh.rb` | ubuntu |
| `xianyu-seller-im` | 官方 OSS 分发目录 `xianyu/seller/commonpro/` | `scripts/update-xianyu.rb` 文件名窗口探测 | ubuntu |
| `boya-central` | 官网下载页 `boyamic.com/support/download`（服务端渲染） | `livecheck` 正则 + `scripts/update-boya.rb` | **macOS** |

**runner 分配原则：能做到的用 ubuntu，有平台限制的才用 macOS。** 本仓库为 public，两类标准 runner 均免费（[GitHub 计费文档](https://docs.github.com/en/billing/concepts/product-billing/github-actions)）。
只有 `boya-central` 必须在 macOS 上跑——它要校验 pkg 的 Apple 签名与公证（`pkgutil --check-signature`、`spctl`），这两个是 macOS 专有命令，而该 pkg 会安装系统级音频驱动，签名校验不能省。
其余三个用 ubuntu：读 dmg 统一走 7-Zip（**需 >= 22.00**，自 22.00 起支持 APFS；Ubuntu 上装 apt 的 `7zip`，勿用 `p7zip-full` 的 16.02），解析 plist 用 Ruby 标准库而非 macOS 的 `plutil`。

- **可手动触发**：Actions → Update Casks → Run workflow，`cask` 选 `all` 或单个
- **人工核对**：`brew livecheck --tap insightop/tap`。`dsh-desktop` 与 `boya-central` 走真实 livecheck；`xianyu-seller-im` 与 `pixso` 因上游无可用版本源而显式 `skip`
- **本地自检**（强制全链路下载校验、不改文件）：
  ```bash
  PIXSO_VERIFY=1  ruby scripts/update-pixso.rb
  DSH_VERIFY=1    ruby scripts/update-dsh.rb
  XIANYU_VERIFY=1 ruby scripts/update-xianyu.rb
  BOYA_VERIFY=1   ruby scripts/update-boya.rb    # 仅 macOS
  ```
- **共享库**：`scripts/lib/cask_update.rb`（7-Zip 定位与版本校验、plist 解析、dmg 内版本读取、cask 改写、下载/清理）

### 各自的探测要点与风险

- **dsh-desktop**：GitHub Releases，用 `:github_latest` 策略读 `/releases/latest`，**天然排除 prerelease**——上游同时发正式版与 `*-beta.1`（如 v2.0.13 与 v2.0.13-beta.1），用默认 Git 策略可能把 beta 当成新版本。
  风险是上游**发布资产改名**：真实发生过一次（v2.0.0 的 `DSH-Desktop-<v>-arm64.dmg` → v2.0.1 起的 `DSH.Desktop-<v>-universal.dmg`，仓库也从 `deepseek-harness-desktop` 更名为 `dsh-desktop`）。脚本不硬编码资产名，而是从 release 资产列表动态选取并反推 `url` 模板，改名时自动同步修正并在 PR 描述里高亮。
- **boya-central**：官网页面直出 `BOYACentral-<version>.pkg`，一个正则即可。风险是页面改版导致失配——失配会**显式报错**而非静默返回旧版本。
  脚本升级时还会校验 Apple 签名与公证、比对包内 App 版本；若上游 **pkg 标识漂移**（真实发生过：1.1.x 的 `com.boyaCentral.BOYA.*` → 1.2.4 的 `com.ccncv.boya.central` / `com.jiayz.virtualaudiodriver`），会自动改写 `uninstall pkgutil` 并在 PR 描述里高亮。
- **xianyu-seller-im**：该 App 无更新 feed、OSS 不可列目录、卖家工作台 SPA 里写死的链接常年滞后（1.2.0 发布后仍指向 1.0.4），因此改为对确定性文件名做存在性探测，并要求 **mac 包与 win 包同时存在**才认定为正式发布。
  风险是上游若**跳号发布**（如 1.2.0 直接到 1.5.0）可能漏检；可用 `XIANYU_PATCH_SPAN` / `XIANYU_MINOR_SPAN` 调整探测窗口。

## 共享 render-cask action（其他项目复用）

本项目提供 cask 渲染的 composite action，任何项目在发布管线中 checkout 本仓库后本地引用即可：

```yaml
- name: 检出 tap 仓库（含共享 render-cask action）
  uses: actions/checkout@v4
  with:
    repository: insightop/homebrew-tap
    token: ${{ secrets.HOMEBREW_TAP_PAT }}   # 仅需读权限的 PAT 或带 contents 写权限
    path: homebrew-tap

- name: 渲染 cask
  uses: ./homebrew-tap/.github/actions/render-cask
  with:
    cask-path: homebrew-tap/Casks/<app>.rb   # cask token 从文件名推导
    version: <版本>
    sha256: <安装包 sha256>
    url: https://vault.insightop.com/<project>/<type>/<app>-<version>-<arch>.dmg
    app-name: <应用显示名>
    desc: <应用描述>          # 可选
    homepage: <项目主页>      # 可选

- name: 提交并推送
  uses: stefanzweifel/git-auto-commit-action@v5
  with:
    repository: homebrew-tap
    commit_message: "chore: update <app> to <版本>"
```

`verified` 字段由 action 自动从 `url` 提取（域名 + 目录前缀），无需手动指定。

## 维护

- 项目接入模板与规范见各项目仓库文档（如 studio：`docs/superpowers/specs/2026-08-16-homebrew-publish-design.md`）
