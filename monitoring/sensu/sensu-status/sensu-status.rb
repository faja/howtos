#!/usr/bin/env ruby

# mcabaj@gmail.com

require 'json'
require 'redis'
require 'rainbow'

if ARGV.length == 0 or ! File.exist?(ARGV[0])
  puts 'Usage: ./redis.rb /path/to/sensu-server/config.json'
  exit 1
end

begin
  settings = JSON.parse(File.open(ARGV[0],'r').read, :symbolize_names => true)
rescue
  puts "#{ARGV[0]} is not a valid json file"
  exit 1
end

def print_state(arg)
  return '['+'ok'.color(:green)+']'               if arg == '0'
  return '['+'warning'.color(:yellow)+']'         if arg == '1'
  return '['+'critical'.color(:red)+']'           if arg == '2'
  return '['+'silenced'.color(:magenta)+']'       if arg == 's'
  return '['+'unknow'.color(:blue)+']'
end

begin
  r=Redis.new(settings[:redis])
  stashes = r.smembers("stashes")
  r.smembers("clients").each do |client|
    keepalive_state = r.hexists("events:#{client}","keepalive") ? print_state(r.lindex("history:#{client}:keepalive",-1)) : print_state('0') 
    printf "%-45s %25s %25s%s\n", client, "keepalive", keepalive_state, stashes.include?("silence/#{client}") ? print_state('s') : nil
    r.keys("history:#{client}:*").each do |check|
      next if check == "history:#{client}:keepalive"
      check_name = check[/history:.+:(.+)/,1]
      printf "%71s %25s%s\n", check_name, print_state(r.lindex(check,-1)), stashes.include?("silence/#{client}/#{check_name}") ? print_state('s') : nil
    end
    puts
  end
rescue => error
  puts error
end
