#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测 DeepSeek Harness 官方客户端是否发布新版并更新本 tap 的
# Casks/deepseek-harness.rb。
#
# 版本来源：App 内置 electron-updater 配置（Contents/Resources/app-update.yml）
#   指向的 generic provider feed：
#     https://download.deepseek.com/dsh-desk/feeds/mac-arm64/nightly-mac.yml
#   该 YAML 含 version、releaseDate，以及 files[].url（指向 .zip 与官方 sha512）。
#
# 为什么不直接用 feed 里的 url：
#   feed 的 files[] 只提供 `.zip`（electron-updater 增量更新用），本 cask 需要
#   `.dmg`（可挂载、可做固定 sha256 校验）。实测二者哈希不同，故 feed 的 sha512
#   不能用于校验 dmg。因此改由 feed 的 version 确定性构造 dmg URL：
#     https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-<version>-mac-arm64.dmg
#
# 流程：
#   1. 抓 nightly-mac.yml → 取 version，与当前 cask version 对比
#   2. 无新版 → 退出（new_version 为空，workflow 不动作）
#   3. 有新版 → 下载 dmg → 自算 sha256（cask 固定校验值）
#              → 读包内 App 版本，确认与 feed 声明一致（防错发包）
#   4. 精准替换 cask 的 version / sha256（url 用 #{version} 模板，无需改）
#   5. 输出 new_version=… 供 workflow 开 PR
#
# 依赖：仅 Ruby 标准库 + 7-Zip（读 dmg 校验包内版本，需 >= 22.00；
#   见 scripts/lib/cask_update.rb）。在 macOS 与 Linux 上均可运行，CI 用 ubuntu。
#
# 环境变量（本地调试用）：
#   DEEPSEEK_VERIFY=1    即使版本相同也强制下载并校验（不修改文件）
#   DEEPSEEK_KEEP_TMP=1  保留临时目录，便于排查

require_relative "lib/cask_update"
require "yaml"
require "digest"

FEED_URL = "https://download.deepseek.com/dsh-desk/feeds/mac-arm64/nightly-mac.yml"
BIN_DIR  = "https://download.deepseek.com/dsh-desk/bin/mac-arm64"
CASK     = File.expand_path("../Casks/deepseek-harness.rb", __dir__)

def log(msg)
  CaskUpdate.log(msg)
end

# dmg 直链由 feed 的版本号确定性构造（见文件头说明）
def dmg_url(version)
  "#{BIN_DIR}/deepseek-harness-#{version}-mac-arm64.dmg"
end

# 抓 feed 并取版本号
def fetch_release
  raw = URI.open(FEED_URL, read_timeout: 60).read

  # feed 含 RFC3339 时间戳（releaseDate），Psych 会将其反序列化为 Time。
  # Ruby 3.1+ 的 YAML.load 已等价于安全加载（类白名单为空），必须显式放行 Time，
  # 否则抛 Psych::DisallowedClass。CI（Ruby 3.3）上曾因此失败。
  # permitted_classes 在 Psych 3.1（macOS 自带 2.6）与 5.x 均可用。
  data = YAML.safe_load(raw, permitted_classes: [Time])
  version = data["version"].to_s
  raise "feed 无 version" if version.empty?

  # 防御：上游若把 feed 挪到别的 channel（如改回 stable），这里会因 URL 404 而显式报错，
  # 不会静默返回旧版本。
  { version: version, release_date: data["releaseDate"].to_s }
rescue Psych::SyntaxError, Psych::DisallowedClass => e
  raise "feed 不是合法 YAML: #{e.message}"
rescue StandardError => e
  raise "获取/解析 feed 失败: #{e.message}"
end

cur = CaskUpdate.read_cask(CASK)
rel = fetch_release
log "当前 cask #{cur[:version]} → feed #{rel[:version]}（releaseDate #{rel[:release_date]}）"

verify_only = ENV["DEEPSEEK_VERIFY"] == "1"
if cur[:version] == rel[:version] && !verify_only
  puts "new_version="
  exit 0
end

workdir = CaskUpdate.make_workdir("update-deepseek", keep_env: "DEEPSEEK_KEEP_TMP")
begin
  url = dmg_url(rel[:version])
  dmg_path = File.join(workdir, "deepseek-harness-#{rel[:version]}-mac-arm64.dmg")
  size = CaskUpdate.download(url, dmg_path)
  log "下载完成 #{size} 字节"

  # 自算 sha256（feed 只有 .zip 的 sha512，不能用于 dmg 校验）
  sha256 = CaskUpdate.sha256_file(dmg_path)
  log "已计算 sha256 #{sha256[0, 16]}…"

  # 交叉校验：读包内版本，确认与 feed 声明一致（防上游发错包/版本对不上）
  inner = CaskUpdate.app_version_from_dmg(dmg_path)
  unless inner == rel[:version]
    raise "版本不一致：feed 声明 #{rel[:version]}，包内 App 为 #{inner}（疑似错发包）"
  end
  log "包内 App 版本 #{inner} 与 feed 声明一致"

  if verify_only
    puts "new_version=#{rel[:version]} (verify)"
    puts "sha256=#{sha256}"
  else
    CaskUpdate.rewrite_cask(CASK, cur[:text], version: rel[:version], sha256: sha256)
    log "已更新 Casks/deepseek-harness.rb → #{rel[:version]} (sha256 #{sha256})"
    puts "new_version=#{rel[:version]}"
  end
ensure
  CaskUpdate.cleanup(workdir, keep_env: "DEEPSEEK_KEEP_TMP")
end

exit 0
