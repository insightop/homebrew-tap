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
├── dsh-desktop.rb       # DSH Desktop（DeepSeek 桌面端，GitHub Releases，手动维护）
├── pixso.rb             # Pixso（博思云创协同设计，官方 homebrew-cask 暂无，自动检测：官方更新通道）
└── <未来项目>.rb         # 每项目一个 cask 文件

.github/actions/render-cask/   # 共享 cask 渲染 action（固定版本模式的项目复用）
```

- **自有项目（latest 模式）**：如 studio——cask 固定指向 vault 的 `?latest` 端点（vault 302 到最新 dmg），`version :latest` + `sha256 :no_check`，**tap 永不随发布更新**，各项目 CI 只需构建 + 上传 R2
- **自有项目（固定版本模式）**：可在 CI 中用共享 render-cask action 更新 cask 的 version/sha256/url（见下）
- **第三方官方 App**（如 xianyu-seller-im、boya-central、pixso）：无法自行构建，cask 指向官方下载源（sha256 固定校验）。**已接入自动检测**（见下节），由定时任务开 PR、人工合并
- `brew` 安装不触发 Gatekeeper quarantine（vault 下载无 quarantine 属性）

## 自动检测新版本

第三方 App 没有发布钩子，因此用定时任务每周探测上游并开 PR（`main` 仍由人工合并，不做自动推送）。

| cask | 版本来源 | 检测方式 |
| --- | --- | --- |
| `pixso` | 官方 electron-updater 通道 `api.pixso.cn/api/upgrade/desktop/bosyun/latest-mac.yml` | 结构化 YAML + 官方 sha512 校验 |
| `boya-central` | 官网下载页 `boyamic.com/support/download`（服务端渲染） | `livecheck` 正则 + `scripts/update-boya.rb` |
| `xianyu-seller-im` | 官方 OSS 分发目录 `xianyu/seller/commonpro/` | `scripts/update-xianyu.rb` 文件名窗口探测 |

- **工作流**：`.github/workflows/update-casks.yml`（每周一 04:00 UTC，`macos-latest`），与 `.github/workflows/update-pixso.yml` 相互独立
- **可手动触发**：Actions → Update Casks → Run workflow，可只跑单个 cask
- **人工核对**：`brew livecheck --tap insightop/tap`。`boya-central` 走真实 livecheck；`xianyu-seller-im` 与 `pixso` 因上游无可用版本源而显式 `skip`
- **本地自检**（强制全链路下载校验、不改文件）：
  ```bash
  BOYA_VERIFY=1   ruby scripts/update-boya.rb
  XIANYU_VERIFY=1 ruby scripts/update-xianyu.rb
  ```
- **脚本需在 macOS 上运行**（依赖 `pkgutil` / `plutil` / `spctl` / `hdiutil`）

### 各自的探测要点与风险

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
