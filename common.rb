require 'pathname'
require 'fileutils'
require 'erb'

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

PROD_USER_NAME  = ENV['PROD_USER_NAME']
PROD_USER_UID   = ENV['PROD_USER_UID']

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
    if conf[:desc].to_s.size > 0
      puts "#{prefix} #{conf[:desc]}".bold
    end

    ret = true
    ret = false if conf[:skip]
    if ret and block_given?
      ret = yield conf, idx 
    end

      
    if ret 
      puts "    > #{cmd}".gray
      `#{cmd}`.to_s.split("\n").map{|e| "     #{e}" }.join "\n"
    else
      puts "    > #{cmd}".gray + "(skip) ".magenta
    end
  end
end

def create_prod_user a_options = {}
  a_username = PROD_USER_NAME
  a_user_uid = PROD_USER_UID

  home_dir = a_options[:home].to_s

  require_prod_user
  header "Create Prod User"
  
  user_passwd = `getent passwd #{PROD_USER_NAME}`.to_s.split ":"

  user_name   = user_passwd.first
  user_uid    = user_passwd[2]
  user_gid    = user_passwd[3]

  #return if user_uid.to_s == a_user_uid.to_s and a_username.to_s == user_name.to_s
  #prodenv1:x:1001:1001::/home/prodenv1:/bin/bash

  cmds = ["useradd", "-u #{a_user_uid}", "-s /bin/bash"]
  cmds.concat ["-d #{home_dir}"] if home_dir.size > 0
  cmds.push a_username
  cmd = cmds.join " "

  do_cmd [
    {cmd: "userdel #{a_username}",  desc: "Remove user #{a_username}"                       },
    {cmd: cmd,                      desc: "Add user #{a_username} with uid = #{a_user_uid}" }
  ]

end

def compile a_in_paths
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
    r = (ERB.new Pathname.new(src_path).read).result
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

def main_exec a_debug = nil
  header "Main Exec"
  if ARGV.size > 0
    puts "Run Bash: " if a_debug
    exec ARGV.join " "
  else  
    cmd = yield
    if cmd.is_a? String
      if a_debug
        puts "exec : #{cmd}"
      else
        exec cmd
      end
    end
  end
end
