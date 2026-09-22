# 共享 render-cask action

`.github/actions/render-cask` 是一个 composite action，用于**渲染标准 Homebrew cask 文件**。
其他项目在自己的发布管线里 checkout 本仓库后，以本地路径引用即可，无需各自手写 cask DSL。

适用于「自有项目、固定版本模式」：每次发版由项目 CI 更新 cask 的 `version` / `sha256` / `url`。
（若是 `version :latest` 模式——如 `studio`——则不需要本 action，tap 不随发布更新。）

## 输入

| 输入 | 必填 | 说明 |
| --- | --- | --- |
| `cask-path` | 是 | 目标 cask 文件路径（如 `homebrew-tap/Casks/<app>.rb`）；**cask token 从文件名推导** |
| `version` | 是 | 版本号（如 `0.1.0-a1b2c3d`） |
| `sha256` | 是 | 安装包 sha256 |
| `url` | 是 | 完整下载 URL |
| `app-name` | 是 | 应用显示名；同时用于 `name` 字段与 `app "<app-name>.app"` 行 |
| `desc` | 否 | 应用描述 |
| `homepage` | 否 | 项目主页 |

## 用法

```yaml
- name: 检出 tap 仓库（含共享 render-cask action）
  uses: actions/checkout@v4
  with:
    repository: insightop/homebrew-tap
    token: ${{ secrets.HOMEBREW_TAP_PAT }}   # 需 contents 写权限
    path: homebrew-tap

- name: 渲染 cask
  uses: ./homebrew-tap/.github/actions/render-cask
  with:
    cask-path: homebrew-tap/Casks/<app>.rb
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

## 生成结果

```ruby
cask "<token>" do
  version "<version>"
  sha256 "<sha256>"

  url "<url>"
  name "<app-name>"
  desc "<desc>"
  homepage "<homepage>"

  app "<app-name>.app"
end
```

`desc` 与 `homepage` 为空时对应行会被省略。

## 注意事项

- **渲染会覆盖目标 cask 文件**。若该 cask 有额外 stanza（如 `livecheck`、`depends_on`、
  `uninstall`、`postflight_steps`、`zap`），本 action 不会保留——它只适用于由项目 CI 全量维护的
  简单 cask。第三方 App 的 cask（见根目录 `AGENTS.md`）是手写维护的，不要用本 action 覆盖。
- action 需要目标仓库的写权限 token（`contents: write`）。
