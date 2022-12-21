require 'yaml'
require 'time'
require 'thread'

class Southy::Config
  attr_reader :config

  def initialize(config_dir = nil)
    @dir = config_dir || "#{ENV['HOME']}/.southy"
    FileUtils.mkdir @dir unless File.directory? @dir

    @timestamps = {}
    load_config :force => true
  end

  def env
    ENV['RUBY_ENV'] || 'development'
  end

  def test?
    env == 'test'
  end

  def smtp_host
    @config[:smtp_host]
  end

  def smtp_port
    @config[:smtp_port]
  end

  def smtp_domain
    @config[:smtp_domain]
  end

  def smtp_account
    @config[:smtp_account]
  end

  def smtp_password
    @config[:smtp_password]
  end

  def slack_api_token
    @config[:slack_api_token]
  end

  def slack_reject_channels
    @config.fetch(:slack_reject_channels, '').split ','
  end

  def slack_accept_channels
    @config.fetch(:slack_accept_channels, '').split ','
  end

  def notify_users?
    @config.fetch(:notify_users, false)
  end

  def fake_slack_user
    @config[:fake_slack_user]
  end

  def reload(options = {})
    options = { :force => false }.merge options
    load_config options
  end

  def save_file(conf, name, json)
    saved_files = saved_files_dir
    FileUtils.mkdir saved_files unless File.directory? saved_files
    itinerary_dir = "#{saved_files}/#{conf}"
    FileUtils.mkdir itinerary_dir unless File.directory? itinerary_dir

    iname = name
    i = 0
    while File.exist? "#{itinerary_dir}/#{iname}" do
      i += 1
      iname = "#{File.basename name, '.*'}_#{i}#{File.extname name}"
    end

    File.open("#{itinerary_dir}/#{iname}", 'w') do |f|
      f.print JSON.pretty_generate(json)
    end
  end

  private

  def load_config(options)
    config = if_updated? config_file, options do
      YAML.load( IO.read(config_file), aliases: true )
    end
    @config = config if config
    @config ||= {}
  end

  def config_file
    "#{@dir}/config.yml"
  end

  def saved_files_dir
    "#{@dir}/saved_files"
  end

  def if_updated?(file_name, options)
    return nil if ! File.exist? file_name

    file = File.new file_name
    last_read = @timestamps[file_name]
    stamp = file.mtime
    if options[:force] || last_read.nil? || stamp > last_read
      @timestamps[file_name] = stamp
      yield
    else
      nil
    end
  end
end
