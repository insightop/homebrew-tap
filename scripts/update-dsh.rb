#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测 DSH Desktop 是否发布新版并更新本 tap 的 Casks/dsh-desktop.rb。
#
# 版本来源：GitHub Releases 的 /releases/latest（天然排除 prerelease）。
#   上游同时发正式版与 *-beta.1 预发布版（如 v2.0.13 与 v2.0.13-beta.1），
#   因此必须用 /releases/latest 而非 /releases 列表。
#
# 为什么不硬编码资产名：
#   macOS 资产命名在 v2.0.0 → v2.0.1 之间变过一次：
#     v2.0.0: DSH-Desktop-<v>-arm64.dmg
#     v2.0.1+: DSH.Desktop-<v>-universal.dmg
#   若把资产名写死，上游再改名时 URL 会 404（且 livecheck 仍显示"有新版本"，难以察觉）。
#   因此本脚本从 release 的资产列表里动态挑 .dmg，并据此反推 cask 的 url 模板。
#
# 流程（仅在有新版时下载安装包）：
#   1. 查 /releases/latest → 与当前 cask version 对比
#   2. 无新版 → 退出（new_version 为空，workflow 不动作）
#   3. 有新版 → 从资产列表挑 .dmg（排除 .blockmap/.yml 等）
#                → 下载 → 挂载读出 App 内嵌版本，确认与 tag 一致（防错发包）
#                → 计算 cask 所需的 sha256
#                → 反推 url 模板；若与 cask 现有 url 不同，一并改写
#   4. 精准替换 version / sha256（必要时含 url），输出 new_version=… 供 workflow 开 PR
#
# 环境变量：
#   DSH_VERIFY=1     即使版本相同也强制下载并校验（不修改文件）
#   DSH_KEEP_TMP=1   保留临时目录，便于排查
#   GH_TOKEN         GitHub API token（CI 里用 secrets.GITHUB_TOKEN，避免匿名限流）
#
# 注意：挂载 dmg 依赖 macOS 的 hdiutil，必须在 macOS 上运行。

require "open-uri"
require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "open3"
require "net/http"
require "uri"

REPO = "anywhere-labs/dsh-desktop"
CASK = File.expand_path("../Casks/dsh-desktop.rb", __dir__)
OPEN_OPTS = { read_timeout: 1800 }.freeze

def log(msg)
  warn "[update-dsh] #{msg}"
end

# 查 /releases/latest；返回 tag、version 与 dmg 资产
def fetch_latest_release
  uri = URI.parse("https://api.github.com/repos/#{REPO}/releases/latest")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github+json"
  req["User-Agent"] = "insightop-homebrew-tap-updater"
  token = ENV["GH_TOKEN"] || ENV["GITHUB_TOKEN"]
  req["Authorization"] = "Bearer #{token}" if token && !token.empty?

  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) do |http|
    http.request(req)
  end
  raise "GitHub API 返回 #{res.code}: #{res.body.to_s[0, 200]}" unless res.code.to_i == 200

  data = JSON.parse(res.body)
  tag = data["tag_name"].to_s
  raise "release 无 tag_name" if tag.empty?
  raise "release 被标记为 prerelease（不该出现在 /releases/latest）" if data["prerelease"]

  version = tag.sub(/\Av/i, "")
  raise "无法从 tag #{tag.inspect} 解析版本号" unless version.match?(/\A\d+(?:\.\d+)+\z/)

  # 只取 .dmg，排除 .dmg.blockmap 等同名前缀资产
  dmgs = data.fetch("assets", []).select { |a| a["name"].to_s.end_with?(".dmg") }
  raise "release #{tag} 中未找到 .dmg 资产" if dmgs.empty?
  raise "release #{tag} 中有多个 .dmg 资产，无法自动判断：#{dmgs.map { |a| a["name"] }.inspect}" if dmgs.size > 1

  dmg = dmgs.first
  { tag: tag, version: version, asset_name: dmg["name"], asset_url: dmg["browser_download_url"] }
end

# 读当前 cask 中的 version / sha256 / url
def current_cask
  text = File.read(CASK)
  version = text[/^  version\s+"([^"]+)"/, 1]
  sha256 = text[/^  sha256\s+"([^"]+)"/, 1]
  url = text[/^  url\s+"([^"]+)"/, 1]
  raise "Casks/dsh-desktop.rb 解析失败（version/sha256/url 缺失）" if version.nil? || sha256.nil? || url.nil?

  { version: version, sha256: sha256, url: url, text: text }
end

# 由「实际资产名 + tag」反推 cask 的 url 模板：把资产名与 tag 里的版本号换成 #{version}
def url_template(asset_name, tag, version)
  name_tpl = asset_name.sub(version) { "\#{version}" }
  unless name_tpl.include?('#{version}')
    raise "无法从资产名 #{asset_name.inspect} 反推 url 模板（未找到版本号 #{version}）"
  end

  tag_tpl = tag.sub(version) { "\#{version}" }
  "https://github.com/#{REPO}/releases/download/#{tag_tpl}/#{name_tpl}"
end

def download(url, dest)
  log "下载 #{url}"
  URI.open(url, **OPEN_OPTS) do |io|
    File.open(dest, "wb") { |f| IO.copy_stream(io, f) }
  end
  File.size(dest)
end

# 挂载 dmg，读出 App 内嵌版本号；确保卸载干净
def app_version_from_dmg(dmg_path)
  out, status = Open3.capture2e("hdiutil", "attach", "-nobrowse", "-readonly", "-plist", dmg_path)
  raise "hdiutil attach 失败: #{out}" unless status.success?

  mount_point = out[/<key>mount-point<\/key>\s*<string>([^<]+)<\/string>/, 1]
  raise "未能从 hdiutil 输出解析挂载点" if mount_point.nil?

  begin
    app = Dir.glob(File.join(mount_point, "*.app")).first
    raise "挂载卷内未找到 .app" if app.nil?

    plist = File.join(app, "Contents", "Info.plist")
    plist_out, pl_status = Open3.capture2e("plutil", "-p", plist)
    raise "plutil 读取 #{plist} 失败" unless pl_status.success?

    version = plist_out[/"CFBundleShortVersionString"\s*=>\s*"([^"]+)"/, 1]
    raise "未能从 Info.plist 解析 CFBundleShortVersionString" if version.nil?

    version
  ensure
    Open3.capture2e("hdiutil", "detach", mount_point, "-quiet")
  end
end

def make_workdir
  dir = Dir.mktmpdir("update-dsh")
  log "DSH_KEEP_TMP=1，保留临时目录 #{dir}" if ENV["DSH_KEEP_TMP"] == "1"
  dir
end

def cleanup(dir)
  return if dir.nil? || ENV["DSH_KEEP_TMP"] == "1"
  return unless Dir.exist?(dir)

  FileUtils.remove_entry(dir)
rescue Errno::ENOENT
  nil
end

# 精准替换 version / sha256；url 模板变化时一并替换
def rewrite_cask(text, version:, sha256:, url: nil)
  text = text.sub(/^  version\s+"[^"]+"/) { %(  version "#{version}") }
  text = text.sub(/^  sha256\s+"[^"]+"/)  { %(  sha256 "#{sha256}") }
  if url
    text = text.sub(/^  url\s+"[^"]+"/) { %(  url "#{url}") }
  end
  File.write(CASK, text)
end

cur = current_cask
rel = fetch_latest_release
log "当前 cask #{cur[:version]} → GitHub 最新 #{rel[:version]}（资产 #{rel[:asset_name]}）"

verify_only = ENV["DSH_VERIFY"] == "1"

# 无新版且非自检：直接退出
if cur[:version] == rel[:version] && !verify_only
  puts "new_version="
  puts "url_changed=false"
  exit 0
end

tpl = url_template(rel[:asset_name], rel[:tag], rel[:version])
url_changed = tpl != cur[:url]

if cur[:version] != rel[:version] && url_changed
  log "⚠️ url 模板也变了："
  log "   现在: #{cur[:url]}"
  log "   新为: #{tpl}"
end

workdir = make_workdir
begin
  dmg_path = File.join(workdir, rel[:asset_name])
  size = download(rel[:asset_url], dmg_path)
  log "下载完成 #{size} 字节"

  inner = app_version_from_dmg(dmg_path)
  unless inner == rel[:version]
    raise "版本不一致：release tag #{rel[:version]}，包内 App 为 #{inner}（疑似错发包）"
  end
  log "包内 App 版本 #{inner} 与 release tag 一致"

  sha256 = Digest::SHA256.file(dmg_path).hexdigest

  if verify_only
    puts "new_version=#{rel[:version]} (verify)"
    puts "sha256=#{sha256}"
    puts "url_changed=#{url_changed}"
    puts "url_template=#{tpl}"
  else
    rewrite_cask(cur[:text], version: rel[:version], sha256: sha256, url: url_changed ? tpl : nil)
    log "已更新 Casks/dsh-desktop.rb → #{rel[:version]} (sha256 #{sha256})"
    puts "new_version=#{rel[:version]}"
    puts "url_changed=#{url_changed}"
  end
ensure
  cleanup(workdir)
end

exit 0
