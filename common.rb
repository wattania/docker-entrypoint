require 'base64'
require 'pathname'
require 'fileutils'
require 'erb'
require 'pp'
require 'json'

def entrypoint?
  Process.pid == 1
end

class String
  def black;          "\e[30m#{self}\e[0m" end
  def red;            "\e[31m#{self}\e[0m" end
  def green;          "\e[32m#{self}\e[0m" end
  def brown;          "\e[33m#{self}\e[0m" end
  def blue;           "\e[34m#{self}\e[0m" end
  def magenta;        "\e[35m#{self}\e[0m" end
  def cyan;           "\e[36m#{self}\e[0m" end
  def gray;           "\e[37m#{self}\e[0m" end

  def bg_black;       "\e[40m#{self}\e[0m" end
  def bg_red;         "\e[41m#{self}\e[0m" end
  def bg_green;       "\e[42m#{self}\e[0m" end
  def bg_brown;       "\e[43m#{self}\e[0m" end
  def bg_blue;        "\e[44m#{self}\e[0m" end
  def bg_magenta;     "\e[45m#{self}\e[0m" end
  def bg_cyan;        "\e[46m#{self}\e[0m" end
  def bg_gray;        "\e[47m#{self}\e[0m" end

  def bold;           "\e[1m#{self}\e[22m" end
  def italic;         "\e[3m#{self}\e[23m" end
  def underline;      "\e[4m#{self}\e[24m" end
  def blink;          "\e[5m#{self}\e[25m" end
  def reverse_color;  "\e[7m#{self}\e[27m" end
end

WORKING_DIR = Pathname.new Dir.pwd

PROD_USER_NAME  = ENV['PROD_USER_NAME']
PROD_USER_UID   = ENV['PROD_USER_UID']

class EnvCompiler
  include ERB::Util

  def initialize a_filepath 
    @filepath = Pathname.new(a_filepath)
    @template = @filepath.read
    @filename = @filepath.basename.to_s
  end

  def env name
    begin
      ENV.fetch name  
    rescue Exception => e
      puts "ENV key not error (#{name}) ".red 
      abort e.message
    end
    
  end

  def render
    begin
      ERB.new(@template).result(binding)
    rescue Exception => e 
      puts "Compile ENV: #{e} : #{@filepath}".red
      abort
    end
  end
end

def line
  "==================================================================== "
  "_____________________________________________________________________".gray
end

def header a_name
  puts
  puts line 
  puts "[#{Time.now}] : " + a_name.to_s 
end

def require_prod_user
  header "Require Prod User" 

  m = []
  if PROD_USER_NAME.to_s.size <= 0
    m.push "Empty PROD_USER_NAME !"   
  end

  if PROD_USER_UID.to_s.size <= 0
    m.push "Empty PROD_USER_UID  !" 
  end  

  if m.size > 0
    puts m.join(", ").bold.red
    raise ".."
  end
end

def do_cmd cmds 
  return unless cmds.is_a? Array 
  header "Do Command"
  length = 0
  cmds.each do |conf| 
    cmd = conf[:cmd].to_s
    length = cmd.size if cmd.size > length
  end

  cmds.each_with_index do |conf, idx| 
    cmd = conf[:cmd]
    prefix = "#{(idx + 1).to_s.rjust(3, ' ')}) "
    desc = ""
    if conf[:desc].to_s.size > 0
      desc = "#{prefix} #{conf[:desc]}".bold.green
    end

    ret = true
    ret = false if conf[:skip]
    if ret and block_given?
      ret = yield conf, idx 
    end

      
    if ret 
      puts "#{desc} > #{cmd}".gray
      `#{cmd}`.to_s.split("\n").map{|e| "     #{e}" }.join "\n"
    else
      puts "#{desc} > #{cmd}".gray + "(skip) ".magenta
    end
  end
end

def create_tun_device
  dev = "/dev/net/tun"
  header "Create Device #{dev}"
  
  dev_net_path = Pathname.new dev
  dev_net_path.dirname.mkpath unless dev_net_path.dirname.exist?

  puts `mknod #{dev} c 10 200` unless dev_net_path.exist?
end

def create_prod_user a_options = {}

  a_username = a_options.fetch :PROD_USER_NAME, PROD_USER_NAME
  a_user_uid = a_options.fetch :PROD_USER_UID, PROD_USER_UID

  home_dir = a_options[:home].to_s

  require_prod_user if PROD_USER_NAME == a_username
  header_txt = "Create Prod User (#{a_username})"
  header header_txt

  cmds = ["useradd"]
  cmds << "-u #{a_user_uid}" if a_user_uid
  cmds << "-s /bin/bash"
  cmds.concat ["-d #{home_dir}"] if home_dir.size > 0
  cmds.push a_username
  cmd = cmds.join " "
 
  existed_user = `id #{a_username}`.strip
  if existed_user.size > 0
    m = existed_user.match /^uid=(\d*)\((\S*)\)\s.*\)$/
    if m
      cmd = nil if m[1] == a_user_uid and m[2] == a_username
    end
  end

  if cmd
    system "userdel #{a_username}"
    res = system cmd 
    raise (header_txt + " ERROR !!").red unless res
  end
end

def require_envs list 
  list.each{|data|
    begin
      ENV.fetch data.to_s 
    rescue Exception => e
      puts "ENV: #{data} ".magenta + e.message.to_s.red
    end
  }
end

def compile a_in_paths, klass = EnvCompiler
  header "Compile Erb"

  txt_size = 0
  m = []
  a_in_paths.each{|in_path| 
    src_path = Pathname.new in_path[:src]
    m.push "SRC Not Exist! : #{src_path}" unless src_path.file?
  }
  if m.size > 0
    m.each{|message| puts message.red }
    raise "error"
  end
  a_in_paths.each{|in_path| txt_size = in_path[:src].to_s.size if in_path[:src].to_s.size > txt_size }
  

  a_in_paths.each_with_index do |in_path, idx|
    a_in_path = in_path[:src].to_s
    src_path = Pathname.new a_in_path

    raise "#{src_path} is not end with .erb" unless src_path.to_s.end_with? ".erb"
      
    dst_path = Pathname.new src_path.to_s.split(".erb").first
    
    opt_dst   = in_path[:dst]
    if opt_dst
      dst_path = Pathname.new opt_dst
    end
     
    unless dst_path.dirname.directory? 
      FileUtils.mkdir_p dst_path.dirname 
    end
    puts "#{(idx + 1).to_s.rjust(3, ' ')}) #{src_path.to_s.ljust(txt_size, " ")} => #{dst_path}"

    r = klass.new(src_path).render
    #r = (ERB.new Pathname.new(src_path).read).result
    File.open(dst_path, 'wb'){|f| f.write r }
  end
  puts
end

def touch a_list 
  return unless a_list.is_a? Array
  a_list.each{|file_config|
    file_path = Pathname.new file_config[:path]
    FileUtils.mkdir_p file_path.dirname unless file_path.dirname.directory?
    `touch #{file_path}` unless file_path.file?
  }
end

def thor_tasks
  if ENV['HOME']
    thor_home = Pathname.new(ENV['HOME']).join ".thor"
    if thor_home.directory?
      `rm -rf #{thor_home}`
    end
  end

  tasks_path = ENV['THOR_TASKS'].to_s 
  if tasks_path.size <= 0
    tasks_path = "/thor_tasks"
  end

  tasks_path = Pathname.new tasks_path
  return unless tasks_path.directory?
  
  tasks_link_path = Pathname.new "/tasks"
  unless File.symlink? tasks_link_path
    FileUtils.ln_s tasks_path, tasks_link_path
  end
=begin
  Dir.glob(tasks_path.join("*.thor").to_s).each{|file|
    thor_file = Pathname.new file
    cmd = "thor install #{file} --force --as=#{thor_file.basename}"
    puts cmd
    `#{cmd}`
  }
=end
end

def script_aliases a_opts = {}
  default_ruby = `which ruby`
  ext_interpreters = {
    rb:     "ruby",
    coffee: "coffee"
  } 

  opts = a_opts 
  opts = {} unless opts.is_a? Hash

  dir   = opts.fetch :dir, "/scripts"
  exts  = opts.fetch :extensions, ["rb"]
  bin_dir = Pathname.new opts.fetch :bin_dir, "/opt/bin"

  # check Env Path for #{bin_dir}
  pp ENV.fetch "PATH"
  if (ENV.fetch "PATH").index(bin_dir.to_s).nil?
    abort "FATAL: $PATH not include #{bin_dir} !!!".bold.red.underline
  end
  
  return unless dir.is_a? String
  return unless exts.is_a? Array
  unless bin_dir.to_s.start_with? "/"
    return abort "Script Bin Path should be full path! (start with \"/\").".red
  end
  puts "bin path => #{bin_dir}"
  `mkdir -p #{bin_dir}` unless bin_dir.directory?
  `chown -R #{PROD_USER_NAME} #{bin_dir}`
  `rm -rf #{bin_dir.join '*'}`

  scripts = []
  script_dir = Pathname.new dir 
  if script_dir.directory?
    
    exts.each_with_index{|ext, idx|
      paths = Dir.glob(script_dir.join "**/*.#{ext}").map{|e| Pathname.new e }.select{|e| e.file? }
      paths.each{|path|
        file_with_ext = File.basename(path.to_s, ".#{ext}")
        cmd = 
        scripts << {
          run_as_prod_user: (path.to_s.split('prod_user').size > 1),
          target: path, 
          ext: ext, 
          cmd: bin_dir.join(file_with_ext.to_s),
          link_name: (WORKING_DIR.join file_with_ext),
          interpreter: ext_interpreters.fetch(ext.to_s.to_sym, "ruby")
        }
      } 
    }
  end

  scripts.each_with_index{|script, idx|
    puts "#{idx + 1}) Create Alias for #{script[:target]} => #{script[:cmd]}".bold
    
    c = "#{script[:interpreter]} #{script[:target]} argv"
    if script[:run_as_prod_user]
      if PROD_USER_NAME.to_s.size <= 0
        puts "No Prod User defined! ".red.bold
        raise "error" 
      end
      c = "runuser #{PROD_USER_NAME} -c '#{c}'"
    end
    
    require_common = nil
    ["/entrypoint-common.rb", "/docker-entrypoint/common.rb"].each{|path|
      next if require_common
      if Pathname.new(path).file?
        require_common = "require '#{path}'"
      end
    }

template = <<-CMD
#!#{default_ruby}
#{require_common}

cmd = "#{c}".sub 'argv', (ARGV.join " ")
puts ("# " + cmd).bold
exec cmd
CMD
    File.open(script[:cmd], "wb"){|f| f.write template }
    `chmod +x #{script[:cmd]}`
  }
end

def main_exec a_debug = nil
  header "Main Exec"
  puts "[INFO] This process id is not number 1 so do not exec command.".green.bold unless entrypoint?
  
  if ARGV.size > 0
    case ARGV.first
    when "no_exec"
      puts "-- no exec --"
    else
      exec ARGV.join " " if entrypoint?
    end
    
  else  
    cmd = yield
    if cmd.is_a? String
      if a_debug
        puts "exec : #{cmd}"
      else
        exec cmd if entrypoint?
      end
    end
  end
end

if ENV['DOCKERFILE_GIT_INFO'].to_s.split("___").last.to_s.size > 0
  class DockerfileGitInfo
    def initialize
      token = ENV['DOCKERFILE_GIT_INFO'].to_s.split("___").last.to_s
      #@info = JWT.decode token, nil, false
      @info = JSON.parse Base64.decode64 token.split("^").join("\n")
    end

    def info
      JSON.parse @info.to_json, object_class: 'OpenStruct'
    end
  end
end

def dockerfile_git_info
  if ENV['DOCKERFILE_GIT_INFO'].to_s.split("___").last.to_s.size > 0
    DockerfileGitInfo.new
  else
    nil
  end
end

if ENV['COMPOSE_GIT_INFO'].to_s.split("___").last.to_s.size > 0
  class ComposeGitInfo
    def initialize
      token = ENV['COMPOSE_GIT_INFO'].to_s.split("___").last.to_s
      @info = JSON.parse Base64.decode64 token.split("^").join("\n")
    end

    def info
      JSON.parse @info.to_json, object_class: 'OpenStruct'
    end
  end
end

if ENV['RUN_CONF']
  RUN_CONF = JSON.parse Base64.decode64 ENV.fetch('RUN_CONF').split("^").join("\n")
  if RUN_CONF.is_a? Hash
    def fetch_run_conf a_key
      if RUN_CONF.has_key? a_key
        RUN_CONF.fetch a_key
      else
        raise "Run CONF has no key : \"#{a_key}\" !!".red
      end
    end
  end
end

if ENV['RUN_VARS']
  RUN_VARS = JSON.parse Base64.decode64 ENV.fetch('RUN_VARS').split("^").join("\n")
  def fetch_run_vars a_key
    if RUN_VARS.has_key? a_key
      RUN_VARS.fetch a_key
    else
      raise "Run VARS has no key : \"#{a_key}\" !!".red
    end
  end
else
  def fetch_run_vars a_key
    
    begin
      ENV.fetch a_key
    rescue Exception => e
      puts e.message.bold.red
      raise "Run VARS has no key : \"#{a_key}\" !!".red unless ENV.keys.include? a_key  
    end
  
  end
end

######################################################
def thor_requires a_self_file, require_lists
  root_script_dir = nil
  thor_root_yml = Pathname.new(File.expand_path a_self_file).dirname.join 'thor.yml'
  if thor_root_yml.file?
    thor_yml_data = YAML.load thor_root_yml.read
    thor_yml_data.each{|thor_name, config|
      if config[:filename] == Pathname.new(a_self_file).basename.to_s
        root_script_dir = Pathname.new(config[:location]).dirname
      end
    }
  else
    root_script_dir = Pathname.new(File.expand_path a_self_file).dirname
  end

  if root_script_dir.nil?
    abort "Please contact administrator.!".red
  else
    require_lists.map{|e| root_script_dir.join e }.each{|name| require name }
  end
end
##############################################################################################################################
##############################################################################################################################
