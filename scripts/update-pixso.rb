#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测 Pixso 桌面端是否发布新版并更新本 tap 的 Casks/pixso.rb。
#
# 版本来源：Pixso 官网下载页暴露的官方 electron-updater 通道
#   https://api.pixso.cn/api/upgrade/desktop/bosyun/latest-mac.yml
#   返回结构化 YAML，含最新 version、dmg 下载地址与该 dmg 的官方 sha512。
#
# 流程（仅在有新版时下载安装包）：
#   1. 抓取 latest-mac.yml，解析最新版本号 → 与当前 cask version 对比
#   2. 无新版 → 退出（new_version 为空，workflow 不动作）
#   3. 有新版 → 下载 dmg → 用 yml 的官方 sha512 校验文件完整性（防篡改/错发包）
#                → 计算 cask 所需的 sha256 → 精准替换 cask 的 version/sha256 两行
#   4. 输出 new_version=… 供 workflow 判断是否开 PR
#
# 环境变量（本地调试用）：
#   PIXSO_VERIFY=1  即使版本相同也强制下载并校验（不修改文件），用于本地验证全链路

require "yaml"
require "open-uri"
require "digest"
require "base64"

YML_URL = "https://api.pixso.cn/api/upgrade/desktop/bosyun/latest-mac.yml"
CASK    = File.expand_path("../Casks/pixso.rb", __dir__)
OPEN_OPTS = { read_timeout: 60 }.freeze

def log(msg)
  warn "[update-pixso] #{msg}"
end

# 从下载页抓取 yml 并解析；从 files 中取出 dmg 项（URL + 官方 sha512）
def fetch_release
  raw = URI.open(YML_URL, **OPEN_OPTS).read
  # 用 YAML.load 而非 safe_load：yml 含 RFC3339 时间戳（releaseDate），
  # 会反序列化为 Time；Ruby 2.6 的 safe_load 类白名单严格（Time 被拒），
  # 而 YAML.load 在 2.6 完整加载、在 3.x 默认安全模式，均兼容 Time。
  # 此 yml 为官方可信数据源，不存在未信任反序列化风险。
  data = YAML.load(raw)
  version = data["version"]
  raise "yml 无 version" if version.nil? || version.empty?

  dmg = data["files"].find { |f| f["url"].to_s.end_with?(".dmg") }
  raise "yml 缺 dmg 项" if dmg.nil?

  { version: version, url: dmg["url"], sha512_b64: dmg["sha512"] }
rescue StandardError => e
  raise "获取/解析 latest-mac.yml 失败: #{e.message}"
end

# 读当前 cask 中的 version / sha256
def current_cask
  text = File.read(CASK)
  version = text[/version\s+"([^"]+)"/, 1]
  sha256  = text[/sha256\s+"([^"]+)"/, 1]
  raise "Casks/pixso.rb 解析失败" if version.nil? || sha256.nil?

  { version: version, sha256: sha256, text: text }
end

# 下载 dmg → 校验 sha512(base64) → 返回 [dmg_bytes, sha256_hex]
def download_and_verify(url, want_sha512_b64)
  log "下载 #{url}"
  body = URI.open(url, **OPEN_OPTS).read
  actual = Base64.strict_encode64(Digest::SHA512.digest(body))
  unless actual == want_sha512_b64
    raise "sha512 校验失败: 期望 #{want_sha512_b64} 实际 #{actual}"
  end

  log "sha512 校验通过"
  [body, Digest::SHA256.hexdigest(body)]
end

# 精准替换 cask 的 version / sha256 两行，不动其它内容
def rewrite_cask(rel, text)
  text = text.sub(/version\s+"([^"]+)"/) { %(version "#{rel[:version]}") }
  text = text.sub(/sha256\s+"([^"]+)"/)  { %(sha256 "#{rel[:sha256]}") }
  File.write(CASK, text)
end

rel = fetch_release
cur = current_cask
log "当前 #{cur[:version]} → 最新 #{rel[:version]}"

if cur[:version] == rel[:version] && ENV["PIXSO_VERIFY"] != "1"
  puts "new_version="
  exit 0
end

body, sha256 = download_and_verify(rel[:url], rel[:sha512_b64])

if ENV["PIXSO_VERIFY"] == "1"
  # 仅校验并打印，不修改文件（本地自检：应与当前 cask sha256 一致）
  puts "new_version=#{rel[:version]} (verify)"
  puts "sha256=#{sha256}"
else
  rewrite_cask(rel, cur[:text])
  log "已更新 Casks/pixso.rb → #{rel[:version]} (sha256 #{sha256})"
  puts "new_version=#{rel[:version]}"
end

exit 0
