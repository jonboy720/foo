#!/opt/chef/embedded/bin/ruby

class LogDirectory
  attr_reader :path

  def files
    Dir.glob(File.join(path, '**', '*.log{,.gz}')).sort
  end

  def logs
    files.map { |file| LogFile.new(file) }
  end

  def join(name)
    File.join(@path, name)
  end
end

class LogFile
  attr_reader :path

  def initialize(path)
    @path = File.expand_path(path.to_s)
  end

  def link?
    File.symlink?(@path)
  end

  def compressed?
    extension == '.gz'
  end

  def target
    link? ? File.expand_path(File.readlink(path), File.dirname(path)) : path
  end

  def extension
    File.extname(@path).downcase
  end
end

class LocalDirectory < LogDirectory
  def initialize(path)
    @path = File.expand_path(path.to_s)
  end

  def links
    logs.select(&:link?)
  end

  def targets
    links.map(&:target).uniq
  end

  def candidates
    files - links - targets
  end

  def names
    candidates.map { |log| log[path.length..-1] }
  end

  def associations
    Hash[names.zip(candidates)]
  end
end

class DeferDirectory < LogDirectory
  def initialize
    @path = File.expand_path(`mktemp -d`.strip)
  end

  def cleanup!
    require 'fileutils'
    puts `tree #{@path}`.strip
    FileUtils.rm_rf(@path)
  end

  def pull!(directory)
    require 'fileutils'
    directory.associations.each do |name, file|
      dest = join(name)
      dir = File.dirname(dest)
      FileUtils.mkdir_p(dir)
      FileUtils.cp_r(file, join(name))
    end
  end

  def compress!
    logs.reject(&:compressed?).each do |log|
      `gzip "#{log.path}"`
    end
  end

  def names
    files.map { |log| log[path.length..-1] }
  end

  def associations
    Hash[names.zip(files)]
  end
end

class RemoteDirectory < LogDirectory
  def initialize(path)
    @path = File.expand_path(path.to_s)
  end

  def pull!(directory)
    directory.associations.each do |name, file|
      dest = join(name)
      dir = File.dirname(dest)
      FileUtils.mkdir_p(dir)
      FileUtils.cp_r(file, join(name))
    end
  end
end

class Program
  def self.run(args)
    # get the local log directory

    path = args.shift

    exit 1 if path.nil?

    local = LocalDirectory.new(path)

    # get the remote log directory

    path = args.shift

    exit 2 if path.nil?

    remote = RemoteDirectory.new(path)

    # create the defer directory

    defer = DeferDirectory.new

    defer.pull!(local)

    defer.compress!

    remote.pull!(defer)

    defer.cleanup!
  end
end

Program.run(ARGV.dup)
