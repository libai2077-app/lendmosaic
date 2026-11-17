#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'pathname'

begin
  root = File.realpath(File.dirname(__FILE__))
  source = File.read(File.join(root, 'app-config.yml'))
  tree = Psych.parse_stream(source)
  raise '配置必须只包含一个 YAML 文档' unless tree.children.length == 1
  mapping = tree.children.first.root
  raise '配置必须是单层键值映射' unless mapping.is_a?(Psych::Nodes::Mapping)
  names = mapping.children.each_slice(2).map { |key, _| key.value }
  raise '配置存在重复键' unless names.uniq.length == names.length
  cfg = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
  keys = %w[app_name project_path scheme team_id bundle_id cloudkit_enabled entitlements_path cloudkit_container_id xcode_developer_dir]
  raise '配置必须是键值映射' unless cfg.is_a?(Hash) && cfg.keys.all? { |k| k.is_a?(String) }
  raise '配置字段缺失或包含未知键' unless cfg.keys.sort == keys.sort
  raise 'cloudkit_enabled 必须是 true 或 false' unless [true, false].include?(cfg['cloudkit_enabled'])
  (keys - ['cloudkit_enabled']).each do |key|
    value = cfg[key]
    raise "#{key} 必须是字符串，不能包含换行、控制字符或占位符" unless value.is_a?(String) && !value.match?(/[\x00-\x1f\x7f]/) && !value.include?('REPLACE_ME')
  end
  %w[app_name project_path scheme team_id bundle_id].each { |k| raise "#{k} 不得为空" if cfg[k].strip.empty? }
  raise 'app_name 只能包含字母数字、下划线、短横线' unless /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/.match?(cfg['app_name'])
  raise 'team_id 必须是 10 位大写字母或数字' unless /\A[A-Z0-9]{10}\z/.match?(cfg['team_id'])
  raise 'bundle_id 格式错误' unless /\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/.match?(cfg['bundle_id'])
  resolve = lambda do |path, directory|
    raise '项目路径必须相对仓库根目录' if Pathname.new(path).absolute? || path.split('/').include?('..')
    full = File.realpath(File.join(root, path))
    raise '项目路径不能通过符号链接跳出仓库' unless full.start_with?(root + '/')
    raise '项目路径类型不正确' unless directory ? File.directory?(full) : File.file?(full)
    full
  end
  raise 'project_path 必须是 .xcodeproj 或 .xcworkspace' unless cfg['project_path'].end_with?('.xcodeproj', '.xcworkspace')
  cfg['project_path'] = resolve.call(cfg['project_path'], true)
  if cfg['cloudkit_enabled']
    raise 'CloudKit 开启时必须设置 entitlements_path 和 cloudkit_container_id' if cfg['entitlements_path'].empty? || cfg['cloudkit_container_id'].empty?
    raise 'CloudKit 容器 ID 格式错误' unless /\AiCloud\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/.match?(cfg['cloudkit_container_id'])
    cfg['entitlements_path'] = resolve.call(cfg['entitlements_path'], false)
  else
    raise 'CloudKit 关闭时两个 CloudKit 配置值应为空' unless cfg['entitlements_path'].empty? && cfg['cloudkit_container_id'].empty?
  end
  dev = cfg['xcode_developer_dir']
  unless dev.empty?
    raise 'Xcode 路径必须为 /Applications 下的 Developer 目录' unless dev.start_with?('/Applications/') && dev.end_with?('.app/Contents/Developer') && File.directory?(dev)
  end
  # Only known names and single-line values are emitted; the shell does not eval them.
  cfg.each { |k, v| puts "#{k.upcase}=#{v}" }
rescue Psych::Exception
  warn '配置错误：YAML 语法、标签或别名不受支持（不输出原始配置内容）。'
  exit 1
rescue StandardError => e
  warn "配置错误：#{e.class}: #{e.message}"
  exit 1
end
