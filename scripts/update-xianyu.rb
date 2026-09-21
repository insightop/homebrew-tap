#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测闲鱼卖家客服（Xianyu Seller IM）是否发布新版并更新本 tap 的 Casks/xianyu-seller-im.rb。
#
# 为什么不能用常规版本源：
#   - App 是 Electron 但没有配置更新 feed（无 SUFeedURL、asar 内无 autoUpdater/feedURL）
#   - OSS 桶不可列目录（NoSuchKey / AccessDenied），也无 latest-mac.yml、RELEASES 等清单
#   - 卖家工作台 SPA 里写死的下载链接常年滞后（1.2.0 发布后仍指向 1.0.4），拿它当版本源会误判
# 因此改为对确定性文件名做「存在性探测」：
#   https://mtl.cn-hangzhou.oss.aliyun-inc.com/xianyu/seller/commonpro/xianyu-seller-im-<x.y.z>-mac.dmg
#
# 流程：
#   1. HEAD 探测以当前 cask 版本为基准的版本窗口（patch +1..+PATCH_SPAN，minor +1..+MINOR_SPAN）
#   2. 命中最大版本 V → 要求同版本 -win.exe 也存在（历史上 mac/win 成对发布），否则视为未发布完
#   3. 无新版 → 退出（new_version 为空，workflow 不动作）
#   4. 有新版 → 下载 dmg，挂载读出 App 内嵌版本号，确认与文件名一致（防错发包）
#              → 计算 cask 所需的 sha256
#   5. 精准替换 cask 的 version/sha256 两行，输出 new_version=… 供 workflow 开 PR
#
# 环境变量（本地调试用）：
#   XIANYU_VERIFY=1    即使版本相同也强制下载并校验（不修改文件），用于本地验证全链路
#   XIANYU_PATCH_SPAN  向前探测的 patch 跨度，默认 20
#   XIANYU_MINOR_SPAN  向前探测的 minor 跨度，默认 5
#
# 注意：挂载 dmg 依赖 macOS 的 hdiutil，必须在 macOS 上运行。

require "open-uri"
require "digest"
require "fileutils"
require "tmpdir"
require "open3"
require "net/http"
require "uri"

BASE_URL = "https://mtl.cn-hangzhou.oss.aliyun-inc.com/xianyu/seller/commonpro"
NAME = "xianyu-seller-im"
CASK = File.expand_path("../Casks/xianyu-seller-im.rb", __dir__)
OPEN_OPTS = { read_timeout: 600 }.freeze
PATCH_SPAN = Integer(ENV.fetch("XIANYU_PATCH_SPAN", "20"))
MINOR_SPAN = Integer(ENV.fetch("XIANYU_MINOR_SPAN", "5"))

def log(msg)
  warn "[update-xianyu] #{msg}"
end

# 读当前 cask 中的 version / sha256
def current_cask
  text = File.read(CASK)
  version = text[/^  version\s+"([^"]+)"/, 1]
  sha256 = text[/^  sha256\s+"([^"]+)"/, 1]
  raise "Casks/xianyu-seller-im.rb 解析失败（version/sha256 缺失）" if version.nil? || sha256.nil?

  { version: version, sha256: sha256, text: text }
end

def artifact_url(version, suffix)
  "#{BASE_URL}/#{NAME}-#{version}-#{suffix}"
end

# HEAD 探测：存在返回 true；404 返回 false；其它状态码或网络错误抛出（避免把故障当成"无新版"）
def exists?(url)
  uri = URI.parse(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 30) do |http|
    res = http.head(uri.request_uri)
    case res.code.to_i
    when 200, 206 then true
    when 404 then false
    else raise "HEAD #{url} 返回 #{res.code}"
    end
  end
rescue Errno::ECONNREFUSED, SocketError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
  raise "HEAD #{url} 网络错误: #{e.message}"
end

def parse_version(version)
  parts = version.split(".").map(&:to_i)
  raise "无法解析版本号 #{version.inspect}" if parts.empty? || parts.any? { |p| p.negative? }

  parts.fill(0, parts.length...3)
end

# 以当前版本为基准生成向前探测的候选版本（patch 优先，再抬 minor）
def candidate_versions(current)
  major, minor, patch = parse_version(current)
  cands = []

  # 同 minor 内递增 patch（最可能的情况）
  (1..PATCH_SPAN).each { |d| cands << "#{major}.#{minor}.#{patch + d}" }
  # 抬 minor：每个 minor 扫 patch 0..PATCH_SPAN
  (1..MINOR_SPAN).each do |dm|
    (0..PATCH_SPAN).each { |p| cands << "#{major}.#{minor + dm}.#{p}" }
  end

  # 去重并保持"从低到高"的顺序，便于直接取最大值
  cands.uniq
end

# 返回最新的「已发布」版本（mac dmg 与 win exe 同时存在），没有则 nil
def find_latest(current)
  found = []
  candidate_versions(current).each do |v|
    next unless exists?(artifact_url(v, "mac.dmg"))

    # mac 命中后先看 win 是否同步（成对发布才算正式发布完成）
    unless exists?(artifact_url(v, "win.exe"))
      log "跳过 #{v}：仅有 mac 包，win 尚未同步（可能仍在发布中）"
      next
    end

    log "发现候选版本 #{v}"
    found << v
  end

  return nil if found.empty?

  # 按语义化版本取最大值，避免依赖探测顺序
  found.max_by { |v| parse_version(v) }
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

def rewrite_cask(text, version:, sha256:)
  text = text.sub(/^  version\s+"[^"]+"/) { %(  version "#{version}") }
  text = text.sub(/^  sha256\s+"[^"]+"/)  { %(  sha256 "#{sha256}") }
  File.write(CASK, text)
end

# 建临时目录；XIANYU_KEEP_TMP=1 时保留并打印路径，便于排查
def make_workdir
  dir = Dir.mktmpdir("update-xianyu")
  log "XIANYU_KEEP_TMP=1，保留临时目录 #{dir}" if ENV["XIANYU_KEEP_TMP"] == "1"
  dir
end

# 清理临时目录；对已消失的路径静默处理，避免清理本身把成功的运行变成失败
def cleanup(dir)
  return if dir.nil? || ENV["XIANYU_KEEP_TMP"] == "1"
  return unless Dir.exist?(dir)

  FileUtils.remove_entry(dir)
rescue Errno::ENOENT
  nil
end

cur = current_cask
log "当前 cask 版本 #{cur[:version]}，开始扫描版本窗口（patch +1..+#{PATCH_SPAN}，minor +1..+#{MINOR_SPAN}）"

latest = find_latest(cur[:version])
verify_only = ENV["XIANYU_VERIFY"] == "1"

if latest.nil?
  if verify_only
    # 本地自检：窗口内无新版时，改为校验当前 cask 版本这一条链路
    log "窗口内未发现更新版本，改为校验当前版本 #{cur[:version]}"
    latest = cur[:version]
  else
    log "窗口内未发现更新的已发布版本"
    puts "new_version="
    exit 0
  end
end

if latest == cur[:version] && !verify_only
  puts "new_version="
  exit 0
end

log "最新版本 #{latest}"

workdir = make_workdir
begin
  dmg_path = File.join(workdir, "#{NAME}-#{latest}-mac.dmg")
  size = download(artifact_url(latest, "mac.dmg"), dmg_path)
  log "下载完成 #{size} 字节"

  inner = app_version_from_dmg(dmg_path)
  unless inner == latest
    raise "版本不一致：文件名 #{latest}，包内 App 为 #{inner}（疑似错发包）"
  end
  log "包内 App 版本 #{inner} 与文件名一致"

  sha256 = Digest::SHA256.file(dmg_path).hexdigest

  if verify_only
    puts "new_version=#{latest} (verify)"
    puts "sha256=#{sha256}"
  else
    rewrite_cask(cur[:text], version: latest, sha256: sha256)
    log "已更新 Casks/xianyu-seller-im.rb → #{latest} (sha256 #{sha256})"
    puts "new_version=#{latest}"
  end
ensure
  cleanup(workdir)
end

exit 0
