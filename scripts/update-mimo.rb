#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测 Xiaomi MiMo Desktop 是否发布新版并更新本 tap 的 Casks/mimo-desktop.rb。
#
# 版本来源：官方发布 manifest（结构化 JSON）
#   https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/manifest.json
#   其中 platforms["mac-arm64"] 直接给出 version、版本化 dmg url、官方 sha256hash 与 size。
#   这比抓页面可靠得多，且自带官方校验值（无需自行推算）。
#
# 背景：该 App 是 Electron，内置 electron-updater（app-update.yml 指向同目录的 generic
#   provider），但顶层 latest-mac.yml 不存在（404），实际 feed 在带版本号的子目录下，
#   且其 files 指向的是 .zip 而非 .dmg。故以 manifest.json 为准。
#
# 流程：
#   1. 抓 manifest.json → 取 mac-arm64 的 version，与当前 cask version 对比
#   2. 无新版 → 退出（new_version 为空，workflow 不动作）
#   3. 有新版 → 校验 manifest 的 url 形态（须是版本化 dmg，而非 latest 固定链接）
#              → 下载 dmg
#              → 先用 manifest 的官方 sha256 校验完整性（防错发包/篡改）
#              → 再读出包内 App 版本，确认与 manifest 声明的版本一致
#   4. 精准替换 cask 的 version / sha256（url 用 #{version} 模板，通常无需改）
#   5. 输出 new_version=… 供 workflow 开 PR
#
# 依赖：仅 Ruby 标准库 + 7-Zip（读 dmg 校验包内版本，需 >= 22.00；
#   见 scripts/lib/cask_update.rb）。故本脚本在 macOS 与 Linux 上均可运行。
#
# 环境变量（本地调试用）：
#   MIMO_VERIFY=1    即使版本相同也强制下载并校验（不修改文件）
#   MIMO_KEEP_TMP=1  保留临时目录，便于排查

require_relative "lib/cask_update"
require "json"
require "digest"

MANIFEST_URL = "https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/manifest.json"
PLATFORM_KEY = "mac-arm64"
CASK = File.expand_path("../Casks/mimo-desktop.rb", __dir__)

def log(msg)
  CaskUpdate.log(msg)
end

# 抓 manifest 并取出 mac-arm64 条目
def fetch_release
  raw = URI.open(MANIFEST_URL, read_timeout: 120).read
  data = JSON.parse(raw)

  entry = data.dig("platforms", PLATFORM_KEY)
  raise "manifest 中缺少 platforms.#{PLATFORM_KEY}" if entry.nil?

  version = entry["version"].to_s
  raise "manifest 的 #{PLATFORM_KEY}.version 为空" if version.empty?

  url = entry["url"].to_s
  sha256 = entry["sha256hash"].to_s
  raise "manifest 的 #{PLATFORM_KEY}.url 为空" if url.empty?
  raise "manifest 的 #{PLATFORM_KEY}.sha256hash 为空" if sha256.empty?

  # 必须拿到「版本化」直链。若上游改成 latest 固定链接，说明我们无法用 sha256 固定校验，
  # 此时明确报错而非静默写入一个不可复现的 URL。
  unless url.include?(version)
    raise "manifest 给出的 url 不含版本号（#{url}），无法作为固定校验源，需人工确认"
  end

  { version: version, url: url, sha256: sha256, size: entry["size"] }
rescue JSON::ParserError => e
  raise "manifest 不是合法 JSON: #{e.message}"
rescue StandardError => e
  raise "获取/解析 manifest 失败: #{e.message}"
end

cur = CaskUpdate.read_cask(CASK)
rel = fetch_release
log "当前 cask #{cur[:version]} → manifest #{rel[:version]}（官方 sha256 #{rel[:sha256][0, 16]}…）"

verify_only = ENV["MIMO_VERIFY"] == "1"
if cur[:version] == rel[:version] && !verify_only
  puts "new_version="
  exit 0
end

workdir = CaskUpdate.make_workdir("update-mimo", keep_env: "MIMO_KEEP_TMP")
begin
  dmg_path = File.join(workdir, "XiaomiMiMo-#{rel[:version]}-arm64.dmg")
  size = CaskUpdate.download(rel[:url], dmg_path)
  log "下载完成 #{size} 字节"

  if rel[:size] && size != Integer(rel[:size])
    raise "大小不一致：manifest 声明 #{rel[:size]}，实际 #{size}"
  end

  # 先用官方 sha256 校验（这是权威校验值）
  actual = CaskUpdate.sha256_file(dmg_path)
  unless actual == rel[:sha256]
    raise "sha256 校验失败：manifest 声明 #{rel[:sha256]}，实际 #{actual}"
  end
  log "官方 sha256 校验通过"

  # 再读包内版本，确认与 manifest 声明一致（防上游发错包）
  inner = CaskUpdate.app_version_from_dmg(dmg_path)
  unless inner == rel[:version]
    raise "版本不一致：manifest 声明 #{rel[:version]}，包内 App 为 #{inner}（疑似错发包）"
  end
  log "包内 App 版本 #{inner} 与 manifest 声明一致"

  if verify_only
    puts "new_version=#{rel[:version]} (verify)"
    puts "sha256=#{actual}"
  else
    CaskUpdate.rewrite_cask(CASK, cur[:text], version: rel[:version], sha256: actual)
    log "已更新 Casks/mimo-desktop.rb → #{rel[:version]} (sha256 #{actual})"
    puts "new_version=#{rel[:version]}"
  end
ensure
  CaskUpdate.cleanup(workdir, keep_env: "MIMO_KEEP_TMP")
end

exit 0
