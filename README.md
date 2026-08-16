# insightop/homebrew-tap

Insightop 组织自有 Homebrew tap，分发多个桌面应用的安装包（cask）。

## 安装

```bash
brew tap insightop/tap
brew install studio
```

## 更新

```bash
brew update && brew upgrade studio
```

## 结构约定（多项目共用）

```
Casks/
├── studio.rb            # Studio 桌面端（macOS arm64）
└── <未来项目>.rb         # 每项目一个 cask 文件

.github/actions/render-cask/   # 共享 cask 渲染 action（各项目复用）
```

- 每个项目在自己的 CI（GitHub Actions）中构建安装包，上传至 Cloudflare R2（vault 下载通道），并自动更新本仓库对应 cask 的 `version` / `sha256` / `url` 三字段
- 本仓库**不手动维护** cask 文件内容，发布流程见各项目仓库的 `.github/workflows/`
- cask 的 `url` 指向 vault 公开下载地址（302 → R2 签名 URL），`brew` 安装不触发 Gatekeeper quarantine

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

## 首次发布前

首个版本发布前，本仓库 cask 中的 `version` / `sha256` / `url` 为占位值；首次 CI 发布成功后自动替换为真实值。

## 维护

- 项目接入模板与规范见各项目仓库文档（如 studio：`docs/superpowers/specs/2026-08-16-homebrew-publish-design.md`）
