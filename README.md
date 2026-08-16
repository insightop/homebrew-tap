# insightop/homebrew-tap

Insightop 组织自有 Homebrew tap，分发多个桌面应用的安装包（cask）。

## 安装

```bash
brew tap insightop/tap
brew install studio xianyu-seller-im
```

## 更新

```bash
# latest 模式（studio：cask 固定，--greedy 强制重拉最新）
brew upgrade --cask --greedy studio

# 固定版本模式（xianyu-seller-im 等：普通升级语义）
brew upgrade --cask xianyu-seller-im
```

## 结构约定（多项目共用）

```
Casks/
├── studio.rb            # Studio 桌面端（macOS arm64，latest 模式：version :latest + sha256 :no_check + 固定 ?latest URL）
├── xianyu-seller-im.rb  # 闲鱼卖家客服（第三方官方 App，固定版本，手动维护）
└── <未来项目>.rb         # 每项目一个 cask 文件

.github/actions/render-cask/   # 共享 cask 渲染 action（固定版本模式的项目复用）
```

- **自有项目（latest 模式）**：如 studio——cask 固定指向 vault 的 `?latest` 端点（vault 302 到最新 dmg），`version :latest` + `sha256 :no_check`，**tap 永不随发布更新**，各项目 CI 只需构建 + 上传 R2
- **自有项目（固定版本模式）**：可在 CI 中用共享 render-cask action 更新 cask 的 version/sha256/url（见下）
- **第三方官方 App**（如 xianyu-seller-im）：无法自行构建，cask 指向官方下载源（sha256 固定校验），**手动维护**
- `brew` 安装不触发 Gatekeeper quarantine（vault 下载无 quarantine 属性）

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
