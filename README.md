# insightop/homebrew-tap

Insightop 组织自有 Homebrew tap，分发桌面应用的安装包（cask）。

## 安装

```bash
brew tap insightop/tap
brew install studio xianyu-seller-im boya-central dsh-desktop deepseek-harness pixso mimo-desktop
```

## 更新

```bash
# latest 模式（studio：cask 固定，--greedy 强制重拉最新）
brew upgrade --cask --greedy studio

# 固定版本模式（其余 cask：普通升级语义）
brew upgrade --cask xianyu-seller-im boya-central dsh-desktop deepseek-harness pixso mimo-desktop
```

## 可用 cask

| cask | 应用 | 说明 |
| --- | --- | --- |
| `studio` | Studio | Insightop 自研桌面端 |
| `xianyu-seller-im` | 闲鱼卖家客服 | 闲鱼商家客服客户端（仅 Apple Silicon） |
| `boya-central` | BOYA Central | 博雅麦克风桌面端，含 CoreAudio 驱动 |
| `dsh-desktop` | DSH Desktop | DeepSeek Harness 桌面端（**社区版**，anywhere-labs 维护，非官方） |
| `deepseek-harness` | DeepSeek Harness | DeepSeek Harness 桌面端（**DeepSeek 官方**，仅 Apple Silicon） |
| `pixso` | Pixso | 博思云创协同设计工具 |
| `mimo-desktop` | Xiaomi MiMo | 小米 MiMo 桌面端（仅 Apple Silicon） |

第三方 App 的 cask 由本仓库的定时任务自动探测上游新版本并开 PR，人工确认后合并，
因此版本通常能及时跟上上游。

## 仓库结构

```
Casks/     每个 cask 一个文件，文件名即 token
scripts/   各 cask 的版本探测脚本 + 共享库
docs/      共享工具的用法文档
.github/   CI：自动检测新版本、cask 渲染 action
```

维护者与编码 agent 请看 [`AGENTS.md`](AGENTS.md)。

## 给其他项目：cask 渲染 action

本仓库提供 composite action，供各项目在发布管线中渲染 cask 的
`version` / `sha256` / `url`，无需各自手写 DSL。用法见
[`docs/render-cask.md`](docs/render-cask.md)。

```yaml
- uses: ./homebrew-tap/.github/actions/render-cask
  with:
    cask-path: homebrew-tap/Casks/<app>.rb
    version: <版本>
    sha256: <安装包 sha256>
    url: https://vault.insightop.com/<project>/<type>/<app>-<version>-<arch>.dmg
    app-name: <应用显示名>
```

> 该 action 会**整文件覆盖**目标 cask，仅适用于由项目 CI 全量维护的简单 cask；
> 第三方 App 的 cask 是手写维护的，不要用它覆盖。
