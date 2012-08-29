#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'json'
require 'yaml'
require 'httpclient'
require 'nokogiri'

config = YAML.load_file('./config.yml')
client = HTTPClient.new
client.set_cookie_store('./cookie.dat')

# load trakt collection
puts "Loading trakt.tv collection `#{config['trakt']['collection']}` for user `#{config['trakt']['user']}` .."
trakt_url = "http://api.trakt.tv/user/#{config['trakt']['collection']}.json/#{config['trakt']['api_key']}/#{config['trakt']['user']}"
trakt_collection = JSON.parse client.get(trakt_url).body

# login to hdbits.org
puts "Logging to hdbits.org as `#{config['hdbits']['user']}` .."
loginPage = Nokogiri::HTML client.get("https://hdbits.org/login").body
lolCode = loginPage.css('form#loginform input[name="lol"]').first.attr('value')

loginParams = { 'uname' => config['hdbits']['user'], 'password' => config['hdbits']['password'], 
                'lol' => lolCode, 'submit' => 'Log in!', 'returnto' => '/' }

res = client.post("https://hdbits.org/login/doLogin", loginParams)

# walk trakt collection and get hdbits results
puts "Scanning hdbits.org for watchlisted movies (#{trakt_collection.size}) .."

output = []
trakt_collection.each do |item|

  out = { 'name' => item['title'], 'imdb_id' => item['imdb_id'], 'results' => [] }
  next if item['imdb_id'].empty?

  params = { 'searchtype' => 'classic', 'imdb' => item['imdb_id'].gsub!('tt',''), 
             'filmexpand' => 1 }
  res = JSON.parse client.post("https://hdbits.org/ajax/search.php", params).body

  res['results'].each do |r|
    out['results'] << { 'id' => r['id'], 'name' => r['name'], 
                        'url' => "http://hdbits.org/details.php?id=#{r['id']}" }
  end

  output << out
end

puts "Saving to `output.json` .."
File.open('output.json', 'w') { |f| f.write(JSON.dump(output)) }

puts "Done."
