# AGENTS.md

面向编码 agent 与仓库维护者的工作指南。使用者文档见 [`README.md`](README.md)。

## 项目概览

Insightop 自有 Homebrew tap，分发桌面应用的 cask。cask 分三类：

| 类型 | 特征 | 维护方式 |
| --- | --- | --- |
| 自有项目（latest 模式） | `version :latest` + `sha256 :no_check` + 固定 `?latest` URL | tap **不随发布更新**；项目 CI 只构建并上传 |
| 自有项目（固定版本模式） | 固定 `version` / `sha256` | 项目 CI 用 [`docs/render-cask.md`](docs/render-cask.md) 的 action 更新 |
| 第三方官方 App | 指向上游下载源 + 固定 `sha256` | **本仓库的定时任务自动探测并开 PR**，人工合并 |

本仓库为 **public**，GitHub 标准 runner（含 macOS）免费。

## 仓库结构

```
Casks/                          # 每个 cask 一个文件，文件名即 token
├── studio.rb                   # 自有，latest 模式
├── xianyu-seller-im.rb         # 第三方，自动检测
├── boya-central.rb             # 第三方，自动检测
├── deepseek-harness.rb         # 第三方（DeepSeek 官方），无探测脚本，人工跟进
├── pixso.rb                    # 第三方，自动检测
└── mimo-desktop.rb             # 第三方，自动检测

scripts/
├── lib/cask_update.rb          # 共享库（见下）
└── update-<cask>.rb            # 每个第三方 cask 一个探测脚本

.github/
├── actions/render-cask/        # 供其他项目复用的 cask 渲染 action
└── workflows/
    ├── update-casks.yml        # 统一入口：每个 cask 一个 job（schedule + workflow_dispatch）
    └── update-cask.yml         # 可复用工作流：单个 cask 的 检测 → 改文件 → 开 PR

docs/
└── render-cask.md              # 共享 action 的用法
```

## 常用命令

```bash
# 人工核对所有 cask 的上游版本
brew livecheck --tap insightop/tap

# 本地自检单个探测脚本（强制全链路下载校验，不修改文件）
PIXSO_VERIFY=1  ruby scripts/update-pixso.rb
XIANYU_VERIFY=1 ruby scripts/update-xianyu.rb
MIMO_VERIFY=1   ruby scripts/update-mimo.rb
BOYA_VERIFY=1   ruby scripts/update-boya.rb    # 仅 macOS

# 语法与 workflow 校验
ruby -c scripts/update-<cask>.rb
actionlint .github/workflows/*.yml

# cask 规范检查
brew audit --cask --strict <token>
```

脚本支持 `<NAME>_KEEP_TMP=1` 保留临时目录便于排查。

## 自动更新系统

**统一入口** `.github/workflows/update-casks.yml`，每天 04:00 UTC 运行，也可手动触发（`cask` 选 `all` 或单个）。
每个 cask 是**独立 job**（非 matrix）：单个失败不影响其它、可单独重跑，手动触发时只跑选中的那个。

探测逻辑集中在可复用的 `.github/workflows/update-cask.yml`，各 job 只声明差异。其输入：

| 输入 | 必填 | 说明 |
| --- | --- | --- |
| `cask` | 是 | cask token |
| `script` | 是 | 探测脚本路径 |
| `file` | 是 | 待更新的 cask 文件路径 |
| `runner` | 是 | `ubuntu-latest` 或 `macos-latest` |
| `source` | 是 | PR 描述里的版本来源（人可读） |
| `extra` | 否 | PR 描述里的补充校验说明 |
| `needs_seven_zip` | 否 | 是否需安装 7-Zip ≥ 22（读 dmg） |

**runner 分配原则：能做到的用 ubuntu，有平台限制的才用 macOS。**

| cask | runner | 7-Zip | 原因 |
| --- | --- | --- | --- |
| `pixso` | ubuntu | — | 纯 Ruby |
| `mimo-desktop` | ubuntu | ✅ | 7-Zip 读 dmg |
| `xianyu-seller-im` | ubuntu | ✅ | 7-Zip 读 dmg（**APFS**） |
| `boya-central` | **macOS** | — | pkg 签名/公证校验依赖 `pkgutil --check-signature`、`spctl`（macOS 专有） |

**7-Zip 版本要求**：读 dmg 需 **≥ 22.00**（自 22.00 起支持 APFS）。Ubuntu 上装 apt 的 `7zip`（23.01）；
**勿依赖 `p7zip-full`**——它在 Ubuntu 24.04 是 transitional 包，且旧版 16.02 读不了 APFS。
脚本会校验版本，不合格即显式报错。

### 约定

- 无新版时脚本安静退出（输出空的 `new_version=`），workflow 不开 PR。
- 只开 PR，**不自动推送 main**；main 由人工合并。
- 分支名 `ci/<cask>-<version>`，已存在则复用（避免重复 PR）。
- 探测到上游「标识漂移」时（如 BOYA 的 pkgutil 变更），脚本会自动同步修正
  并在 PR 描述里高亮，提示人工重点复核。

## 各 cask 的探测要点与风险

- **boya-central**：官网页面直出 `BOYACentral-<version>.pkg`，一个正则即可。风险是页面改版导致失配——失配会**显式报错**而非静默返回旧版本。
  脚本升级时还会校验 Apple 签名与公证、比对包内 App 版本；若上游 **pkg 标识漂移**（真实发生过：1.1.x 的 `com.boyaCentral.BOYA.*` → 1.2.4 的 `com.ccncv.boya.central` / `com.jiayz.virtualaudiodriver`），会自动改写 `uninstall pkgutil` 并在 PR 描述里高亮。
- **xianyu-seller-im**：该 App 无更新 feed、OSS 不可列目录、卖家工作台 SPA 里写死的链接常年滞后（1.2.0 发布后仍指向 1.0.4），因此改为对确定性文件名做存在性探测，并要求 **mac 包与 win 包同时存在**才认定为正式发布。
  风险是上游若**跳号发布**（如 1.2.0 直接到 1.5.0）可能漏检；可用 `XIANYU_PATCH_SPAN` / `XIANYU_MINOR_SPAN` 调整探测窗口。
- **mimo-desktop**：官方发布 manifest 是结构化 JSON，`platforms["mac-arm64"]` 直接给出**版本化 dmg 地址 + 官方 sha256**，故用 `:json` 策略取版本，脚本再拿官方 sha256 校验包并核对包内版本。这是本仓库里数据源质量最好的一类（不必自行推算校验值）。
  上游同时提供固定 URL（`XiaomiMiMo-latest-arm64.dmg`）；本 cask 刻意用版本化 URL 以便固定校验。脚本**要求 manifest 的 url 必须含版本号**，若上游某天改成只给 latest 链接，会显式报错而非静默写入不可复现的 URL。
  该 App 内置 electron-updater（`app-update.yml` 指向同目录 generic provider），但顶层 `latest-mac.yml` 为 404、实际 feed 在带版本号的子目录且指向 `.zip`，故未采用该通道。

## 共享库 `scripts/lib/cask_update.rb`

四个探测脚本共用，避免重复实现：

- 7-Zip 定位与版本校验（≥ 22.00；优先 `7zz`，兼容 `7z`）
- XML plist 解析（用 REXML，**不依赖 macOS 的 `plutil`**）
- dmg 内顶层 App 版本读取（用 7-Zip 流式抽取，**不依赖 `hdiutil`**）
- cask 的 `version` / `sha256` / `url` 读写
- 下载、临时目录创建与清理

跨平台注意点（都已踩过坑）：

- `7z e -so` 抽取 dmg 内文件时，APFS 资源分支字节会紧跟 `</plist>`，需按 `</plist>` 截断再解析。
- dmg 内 app 可能在根目录（闲鱼）或一层子目录内（mimo），匹配时允许一层前缀。
- 7-Zip 版本号解析不能被 `[64]` 这类架构标记干扰（否则会静默放行过旧版本）。

## 未公证 App 的 Gatekeeper 处理

Homebrew 下载安装包后会打上 `com.apple.quarantine`。若上游只做 Developer ID 签名、**未做 Apple 公证**，
首次启动会被 Gatekeeper 拦下并弹「无法验证开发者」。这类 cask 需在安装后清除该标记：

```ruby
app "Xxx.app"

postflight_steps do
  run "/usr/bin/xattr",
      args: ["-dr", "com.apple.quarantine", "{{appdir}}/Xxx.app"],
      sudo: false
end
```

`{{appdir}}` 由 Homebrew 安装时展开（默认 `/Applications`，可用 `HOMEBREW_CASK_OPTS="--appdir=..."` 覆盖），
中文/带空格的 App 名同样适用。`postflight_steps` 排在 `app` artifact 之后执行，故不会被移动时的
xattr 复制覆盖。

**判定某个 cask 是否需要它**：

```bash
spctl -a -vvv -t exec /Applications/Xxx.app
# accepted                → 已公证，无需处理
# rejected / Unnotarized  → 未公证，需加 postflight_steps
```

当前状态：

| cask | 上游公证 | 处理 |
| --- | --- | --- |
| `studio` | 未公证 | 已有 `postflight_steps` |
| `xianyu-seller-im` | 未公证 | 已有 `postflight_steps` |
| `boya-central` | 已公证（pkg） | 不需要 |
| `pixso` | 已公证 | 不需要 |
| `mimo-desktop` | 已公证 | 不需要 |
| `deepseek-harness` | 已公证（Developer ID: Hangzhou DeepSeek） | 不需要 |

> 清 quarantine 只去掉下载来源的隔离标记，**不影响代码签名校验**（`codesign --verify` 仍通过）；
> 它解决的是「未公证导致的首次启动弹窗」，不是绕过签名验证。

## 添加新 cask

1. 先取证，别凭猜测写：挂载上游 dmg/pkg，读 `Contents/Info.plist`（版本、bundle id、
   `LSMinimumSystemVersion`），并确认架构（`arm64` / `x86_64` / universal，必要时加
   `depends_on arch:`）。
2. 判定公证状态（见上节），未公证才加 `postflight_steps`。
3. 确定版本源：优先结构化 JSON/YAML（可固定校验），其次服务端渲染的页面，
   最后才考虑文件名探测。避免使用上游常年不更新的固定链接当版本源。
4. 写 `Casks/<token>.rb`，`livecheck` 用真实可用的源；若上游确实没有版本源，
   显式 `skip` 并注明替代检测方式。
5. 若有自动化，加 `scripts/update-<cask>.rb`（复用 `scripts/lib/cask_update.rb`），
   并在 `.github/workflows/update-casks.yml` 加一个 job（选 runner 与 `needs_seven_zip`）。
6. 验证：`brew livecheck`、伪造旧版本跑一次 upgrade 路径、`brew audit --cask --strict`、
   最好再做一次真实 `brew install`。
7. 更新 `README.md` 的 cask 表与本文件的对应章节。

## PR 与提交约定

- 提交信息用中文，格式 `<type>: <摘要>`（`feat` / `fix` / `refactor` / `ci` / `docs` / `chore`）。
- 一个提交做一件事；涉及升级时在正文写清**为什么**（尤其上游标识漂移这类非显然的改动）。
- 不要自动推送 `main`；自动检测开出的 PR 一律人工确认后合并。
