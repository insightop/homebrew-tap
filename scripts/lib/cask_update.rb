# frozen_string_literal: true

# 本 tap 自动更新脚本的共享工具。
#
# 设计目标：让同一份探测逻辑既能在 macOS 上跑（开发者本机），也能在 Linux 上跑
# （GitHub Actions 的 ubuntu runner，成本更低且足够），因此不依赖 macOS 专有命令。
#
# 关于 dmg 解析：
#   macOS 有 hdiutil，Linux 没有。7-Zip 自 22.00 起支持 APFS，可跨平台读取 dmg
#   并直接抽取内部文件，故统一用 7-Zip，避免两套实现。
#   注意：Ubuntu 24.04 自带的 p7zip 是 16.02（不支持 APFS），必须用 apt 的
#   `7zip` 包（23.01）或更新版本；macOS 上 `brew install sevenzip` 提供 `7zz`。
#
# 关于 plist 解析：
#   不依赖 macOS 的 plutil，改用 Ruby 标准库（REXML）直接解析 XML plist。

require "open-uri"
require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "open3"
require "net/http"
require "uri"
require "rexml/document"

module CaskUpdate
  module_function

  # ---- 7-Zip 定位 --------------------------------------------------------

  # 找到可用的 7-Zip 可执行文件。
  # Ubuntu 24.04 的 apt `7zip` 装的是 `7zz`；p7zip 装的是 `7z`（16.02，不支持 APFS）。
  # 因此优先 7zz，其次 7z，并在版本过低时明确报错而非静默失败。
  def seven_zip_bin
    @seven_zip_bin ||= begin
      bin = %w[7zz 7z 7za].find { |c| system("command -v #{c} >/dev/null 2>&1") }
      raise "未找到 7-Zip（7zz/7z）。Ubuntu 请 `apt-get install -y 7zip`；macOS 请 `brew install sevenzip`" if bin.nil?

      # p7zip 会先打印架构标记（如 "7-Zip [64] 17.05"），故先从含 7-Zip 的那一行里
      # 取第一个 x.y 形式的数字，避免误匹配版权年份等信息。
      banner = `#{bin} 2>&1`
      line = banner.lines.find { |l| l.include?("7-Zip") } || banner
      version = line[/\b(\d+\.\d+)\b/, 1]
      if version.nil?
        raise "无法识别 7-Zip 版本（#{bin} 输出异常）: #{banner[0, 120].inspect}"
      end
      if Gem::Version.new(version) < Gem::Version.new("22.00")
        raise "7-Zip #{version} 过旧（读取 APFS dmg 需 >= 22.00）。" \
              "Ubuntu 请装 apt 的 `7zip`（23.01），勿用 `p7zip-full`（16.02）"
      end

      log "使用 7-Zip: #{bin} #{version}"
      bin
    end
  end

  # ---- plist 解析 --------------------------------------------------------

  # 解析 XML plist 文本，返回 { key => value }（仅取字符串值，够用且避免依赖 plist gem）
  def parse_plist(xml)
    # 7z 以 -so 抽取 dmg 内文件时，APFS 资源分支的字节会紧跟在 </plist> 之后，
    # 导致整体不是合法 UTF-8。截取到 </plist> 为止即可，同时按 UTF-8 宽松处理。
    xml = xml.to_s.dup.force_encoding("UTF-8")
    xml = xml[0, xml.index("</plist>").to_i + "</plist>".length] if xml.include?("</plist>")
    xml = xml.scrub("")

    doc = REXML::Document.new(xml)
    root = doc.elements["plist/dict"]
    raise "plist 结构异常（无 plist/dict 根）" if root.nil?

    result = {}
    key = nil
    root.each_element do |el|
      case el.name
      when "key" then key = el.text.to_s
      when "string" then result[key] = el.text.to_s if key
      end
    end
    result
  end

  # ---- dmg 解析 ----------------------------------------------------------

  # 从 dmg 中读出顶层 .app 的 Info.plist，返回 { key => value }。
  # 用 `7z e -so` 流式抽取，避免为了一个 plist 解出整个几百 MB 的镜像。
  def app_info_from_dmg(dmg_path)
    bin = seven_zip_bin

    # 先列出条目，定位顶层 app 的 Info.plist（排除 Helper.app / Frameworks 里的）
    list, status = Open3.capture2e(bin, "l", "-slt", dmg_path)
    raise "7z 列出 #{File.basename(dmg_path)} 失败: #{list[0, 300]}" unless status.success?

    # app 可能在根目录（闲鱼），也可能位于一个顶层子目录内（dsh 为
    # "<App> <version>-<arch>/<App>.app/..."）。因此允许最多一层目录前缀。
    # 用 [^/]+ 限定每段不含斜杠，可自然排除 Frameworks 里嵌套的 Helper.app。
    candidates = list.scan(/^Path = (.+)$/).flatten
    top_app = candidates.find { |p| p.match?(%r{\A(?:[^/]+/)?[^/]+\.app/Contents/Info\.plist\z}) }
    raise "dmg 内未找到顶层 .app/Contents/Info.plist（包结构可能已变）" if top_app.nil?

    xml, ex_status = Open3.capture2e(bin, "e", "-so", dmg_path, top_app)
    raise "7z 抽取 #{top_app} 失败" unless ex_status.success?

    parse_plist(xml)
  end

  # 从 dmg 中读出顶层 .app 的版本号
  def app_version_from_dmg(dmg_path)
    info = app_info_from_dmg(dmg_path)
    version = info["CFBundleShortVersionString"]
    raise "未能从 Info.plist 解析 CFBundleShortVersionString" if version.nil? || version.empty?

    version
  end

  # ---- cask 读写 ---------------------------------------------------------

  # 读 cask 的 version / sha256 / url 及原始文本
  def read_cask(path)
    raise "cask 文件不存在: #{path}" unless File.exist?(path)

    text = File.read(path)
    version = text[/^  version\s+"([^"]+)"/, 1]
    sha256 = text[/^  sha256\s+"([^"]+)"/, 1]
    url = text[/^  url\s+"([^"]+)"/, 1]
    raise "#{path} 解析失败（version/sha256 缺失）" if version.nil? || sha256.nil?

    { version: version, sha256: sha256, url: url, text: text }
  end

  # 精准替换 cask 的 version / sha256（可选 url），不动其它内容
  def rewrite_cask(path, text, version:, sha256:, url: nil)
    text = text.sub(/^  version\s+"[^"]+"/) { %(  version "#{version}") }
    text = text.sub(/^  sha256\s+"[^"]+"/)  { %(  sha256 "#{sha256}") }
    text = text.sub(/^  url\s+"[^"]+"/)     { %(  url "#{url}") } if url
    File.write(path, text)
  end

  # ---- 杂项 --------------------------------------------------------------

  def log(msg)
    warn "[update-cask] #{msg}"
  end

  def download(url, dest)
    log "下载 #{url}"
    URI.open(url, read_timeout: 1800) do |io|
      File.open(dest, "wb") { |f| IO.copy_stream(io, f) }
    end
    File.size(dest)
  end

  def sha256_file(path)
    Digest::SHA256.file(path).hexdigest
  end

  # 建临时目录；keep_env 为对应环境变量名，置 1 时保留并打印路径
  def make_workdir(prefix, keep_env:)
    dir = Dir.mktmpdir(prefix)
    log "#{keep_env}=1，保留临时目录 #{dir}" if ENV[keep_env] == "1"
    dir
  end

  # 清理临时目录；对已消失的路径静默处理，避免清理本身把成功的运行变成失败
  def cleanup(dir, keep_env:)
    return if dir.nil? || ENV[keep_env] == "1"
    return unless Dir.exist?(dir)

    FileUtils.remove_entry(dir)
  rescue Errno::ENOENT
    nil
  end
end
