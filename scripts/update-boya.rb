#!/usr/bin/env ruby
# frozen_string_literal: true

# 自动检测 BOYA Central（博雅麦克风桌面端）是否发布新版并更新本 tap 的 Casks/boya-central.rb。
#
# 版本来源：官网下载页 https://www.boyamic.com/support/download
#   该页服务端渲染，直接输出 <a href="https://oss.boyamic.com/app/BOYACentral-<version>.pkg">
#   （中文 /cn/support/download 与德文页内容一致）。桌面端自身无可用更新接口：
#   它是 Qt 应用（非 Electron / 非 Sparkle），二进制里内置的 checkUpdateApp 已被上游注释掉。
#
# 流程（仅在有新版时下载安装包）：
#   1. 抓官网下载页，正则提取最新版本号 → 与当前 cask version 对比
#   2. 无新版 → 退出（new_version 为空，workflow 不动作）
#   3. 有新版 → 下载 pkg
#                → 校验 Apple 签名与公证（pkgutil --check-signature + spctl）
#                → 展开读出 App 内嵌版本，确认与文件名版本一致（防错发包）
#                → 读出实际 pkg 标识（identifier），与 cask 的 uninstall pkgutil 对比
#                → 计算 cask 所需的 sha256
#   4. 改写 cask 的 version / sha256；若 pkg 标识漂移，同步改写 uninstall pkgutil 列表
#   5. 输出 new_version=… 与 pkgutil_changed=… 供 workflow 开 PR
#
# 环境变量（本地调试用）：
#   BOYA_VERIFY=1      即使版本相同也强制下载并校验（不修改文件），用于本地验证全链路
#   BOYA_KEEP_TMP=1    保留临时目录（含下载的 pkg 与展开结果），便于排查
#
# 注意：本脚本依赖 macOS 自带命令（pkgutil / plutil / spctl），必须在 macOS 上运行。

require "open-uri"
require "digest"
require "fileutils"
require "tmpdir"
require "open3"

PAGE_URL = "https://www.boyamic.com/support/download"
VERSION_RE = %r{BOYACentral[._-]v?(\d+(?:\.\d+)+)\.pkg}i
CASK = File.expand_path("../Casks/boya-central.rb", __dir__)
OPEN_OPTS = { read_timeout: 300 }.freeze

def log(msg)
  warn "[update-boya] #{msg}"
end

# 抓官网下载页，提取最新版本号
def fetch_latest_version
  html = URI.open(PAGE_URL, **OPEN_OPTS).read
  version = html[VERSION_RE, 1]
  raise "官网下载页未匹配到 BOYACentral-<version>.pkg（页面结构可能已改版）" if version.nil?

  version
rescue StandardError => e
  raise "获取/解析官网下载页失败: #{e.message}"
end

# 读当前 cask 的 version / sha256 / uninstall pkgutil 标识
def current_cask
  text = File.read(CASK)
  version = text[/^  version\s+"([^"]+)"/, 1]
  sha256 = text[/^  sha256\s+"([^"]+)"/, 1]
  raise "Casks/boya-central.rb 解析失败（version/sha256 缺失）" if version.nil? || sha256.nil?

  pkgutil = text[/uninstall pkgutil: \[(.*?)\]/m, 1].to_s.scan(/"([^"]+)"/).flatten
  { version: version, sha256: sha256, pkgutil: pkgutil, text: text }
end

def download(url, dest)
  log "下载 #{url}"
  URI.open(url, **OPEN_OPTS) do |io|
    File.open(dest, "wb") { |f| IO.copy_stream(io, f) }
  end
  File.size(dest)
end

# 校验 Apple 签名链与公证；pkg 未通过则直接失败，避免把可疑包写进 cask
def verify_apple_signature(pkg_path)
  out, status = Open3.capture2e("pkgutil", "--check-signature", pkg_path)
  log out.strip
  raise "pkgutil --check-signature 失败：签名校验未通过" unless status.success?
  raise "pkg 未通过 Apple 公证（Notarization: trusted 缺失）" unless out.include?("trusted by the Apple notary service")

  _sp_out, sp_status = Open3.capture2e("spctl", "-a", "-vvv", "-t", "install", pkg_path)
  raise "spctl 拒绝该 pkg（Gatekeeper 校验失败）" unless sp_status.success?

  log "Apple 签名与公证校验通过"
end

# 展开 pkg，读出 App 内嵌版本与各子包标识
def inspect_pkg(pkg_path, workdir)
  expand_dir = File.join(workdir, "expanded")
  _out, status = Open3.capture2e("pkgutil", "--expand-full", pkg_path, expand_dir)
  raise "pkgutil --expand-full 失败" unless status.success?

  info_plist = Dir.glob(File.join(expand_dir, "**", "Payload", "BOYA Central.app", "Contents", "Info.plist")).first
  raise "展开后未找到 BOYA Central.app/Contents/Info.plist（包结构可能已变）" if info_plist.nil?

  plist_out, pl_status = Open3.capture2e("plutil", "-p", info_plist)
  raise "plutil 读取 Info.plist 失败" unless pl_status.success?

  app_version = plist_out[/"CFBundleShortVersionString"\s*=>\s*"([^"]+)"/, 1]
  bundle_id = plist_out[/"CFBundleIdentifier"\s*=>\s*"([^"]+)"/, 1]
  raise "未能从 Info.plist 解析 CFBundleShortVersionString" if app_version.nil?

  # 每个子包一个 PackageInfo，identifier= 即安装后 pkgutil receipt 的标识
  identifiers = Dir.glob(File.join(expand_dir, "*.pkg", "PackageInfo")).sort.map do |pi|
    File.read(pi)[/identifier="([^"]+)"/, 1]
  end.compact
  raise "未从展开结果解析到任何 pkg identifier" if identifiers.empty?

  { app_version: app_version, bundle_id: bundle_id, identifiers: identifiers.uniq }
end

# 精准替换 version / sha256 两行，以及（必要时）uninstall pkgutil 列表
def rewrite_cask(text, version:, sha256:, pkgutil: nil)
  text = text.sub(/^  version\s+"[^"]+"/) { %(  version "#{version}") }
  text = text.sub(/^  sha256\s+"[^"]+"/)  { %(  sha256 "#{sha256}") }

  unless pkgutil.nil? || pkgutil.empty?
    body = pkgutil.map { |id| %(    "#{id}",\n) }.join
    rewritten = text.sub(/(uninstall pkgutil: \[\n).*?(\n  \])/m) do
      "#{Regexp.last_match(1)}#{body.chomp}#{Regexp.last_match(2)}"
    end
    # 漂移已确认但改不动（例如 cask 里没有 uninstall pkgutil 段）时必须报错，
    # 否则会写出 version/sha256 与 uninstall 标识不一致的 cask，且 PR 描述谎称已改写。
    raise "检测到 pkg 标识漂移，但未能在 cask 中定位 uninstall pkgutil 列表，需人工处理" if rewritten == text

    text = rewritten
  end

  File.write(CASK, text)
end

# 建临时目录；BOYA_KEEP_TMP=1 时保留并打印路径，便于排查
def make_workdir
  if ENV["BOYA_KEEP_TMP"] == "1"
    dir = Dir.mktmpdir("update-boya")
    log "BOYA_KEEP_TMP=1，保留临时目录 #{dir}"
    dir
  else
    Dir.mktmpdir("update-boya")
  end
end

# 清理临时目录。Dir.mktmpdir 在块退出时也会自行清理，故这里只处理"非块形式"的目录，
# 并对已消失的路径静默处理（避免清理本身把成功的运行变成失败）。
def cleanup(dir)
  return if dir.nil? || ENV["BOYA_KEEP_TMP"] == "1"
  return unless Dir.exist?(dir)

  FileUtils.remove_entry(dir)
rescue Errno::ENOENT
  nil
end

latest = fetch_latest_version
cur = current_cask
log "当前 #{cur[:version]} → 官网 #{latest}"

verify_only = ENV["BOYA_VERIFY"] == "1"
if cur[:version] == latest && !verify_only
  puts "new_version="
  puts "pkgutil_changed=false"
  exit 0
end

url = "https://oss.boyamic.com/app/BOYACentral-#{latest}.pkg"

workdir = make_workdir
begin
  pkg_path = File.join(workdir, "BOYACentral-#{latest}.pkg")
  size = download(url, pkg_path)
  log "下载完成 #{size} 字节"

  verify_apple_signature(pkg_path)
  info = inspect_pkg(pkg_path, workdir)

  unless info[:app_version] == latest
    raise "版本不一致：文件名 #{latest}，包内 App 为 #{info[:app_version]}（疑似错发包）"
  end
  log "包内 App 版本 #{info[:app_version]}（#{info[:bundle_id]}）与文件名一致"

  sha256 = Digest::SHA256.file(pkg_path).hexdigest
  drifted = info[:identifiers].sort != cur[:pkgutil].sort

  if drifted
    log "⚠️ pkg 标识漂移："
    log "   cask 现有: #{cur[:pkgutil].inspect}"
    log "   pkg  实际: #{info[:identifiers].inspect}"
  else
    log "pkg 标识与 cask 现有 uninstall pkgutil 一致"
  end

  if verify_only
    puts "new_version=#{latest} (verify)"
    puts "sha256=#{sha256}"
    puts "pkgutil_changed=#{drifted}"
    puts "pkgutil_actual=#{info[:identifiers].join(",")}"
  else
    rewrite_cask(cur[:text], version: latest, sha256: sha256, pkgutil: drifted ? info[:identifiers] : nil)
    log "已更新 Casks/boya-central.rb → #{latest} (sha256 #{sha256})"
    puts "new_version=#{latest}"
    puts "pkgutil_changed=#{drifted}"
    puts "pkgutil_actual=#{info[:identifiers].join(",")}"
  end
ensure
  cleanup(workdir)
end

exit 0
