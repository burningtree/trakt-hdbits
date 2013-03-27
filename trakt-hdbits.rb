#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'bundler/setup'

require 'json'
require 'yaml'
require 'httpclient'
require 'nokogiri'
require 'cgi'
require 'digest/md5'

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

hdbitsLoginParams = { 'uname' => config['hdbits']['user'], 'password' => config['hdbits']['password'], 
                      'lol' => lolCode, 'submit' => 'Log in!', 'returnto' => '/' }

client.post("https://hdbits.org/login/doLogin", hdbitsLoginParams)

def url(type, id)

  case type
    when "hdbits"
      "http://hdbits.org/details.php?id=#{id}"
    when "cinematik"
      "http://cinematik.net/details.php?id=#{id}"
    when "torrentleech"
      "http://torrentleech.org/torrent/#{id}"
  end

end

def get_cached(client, url)
  out = false
  md5 = Digest::MD5.hexdigest(url)
  p md5
  file = "./cache/"+md5

  if File.exists?(file)
    out = File.open(file).read
  else
    out = client.get(url).body
    File.open(file, 'w') { |f| f.write(out) }
  end
  return out
end

def torrentleech_search(client, name, imdb)
  page = client.get("http://torrentleech.org/torrents/browse/index/query/#{CGI.escape(name)}/categories/1,8,9,10,11,12,13,14,15,29").body
  if page.match(/There are no results found/)
    return []
  end
  out = []
  res = Nokogiri::HTML page
  res.css("table#torrenttable tr").each do |r|
    id = r.attr("id")
    if id
      textpg = get_cached(client, "http://torrentleech.org/torrents/torrent/nfotext?torrentID=#{id}")
      if textpg.match(imdb)
        name = r.css("td.name span.title a").first.content
        name_match = name.match(/^(.+) \(\d{4}\) (.+)$/)
        out << { "id" => id, "name" => (name_match ? name_match[2] : name), "type" => "torrentleech" }
      end
    end
  end
  return out
end

def cinematik_search(client, imdb)
  page = client.get("http://cinematik.net/browse.php?search=#{ imdb }&cat=0&incldead=1&sort=1&type=asc&srchdtls=1").body
  if page.match(/Try again with a refined search string./)
    return []
  end
  
  out = []
  res = Nokogiri::HTML page
  res.css("a.brolin").each do |r|
    match = r.attr("href").match(/^details.php\?id=(\d+)&hit=1$/)
    if match
      name_match = r.content.match(/^(.+) \(\d{4}\) (.+)$/)
      out << { "id" => match[1], "name" => (name_match ? name_match[2] : r.content), "type" => "cinematik"  }
    end
  end

  return out
end

# login to cinematik.net

puts "Logging to cinematik.net as `#{config['cinematik']['user']}` .."
cinematikLoginParams = { 'username' => config['cinematik']['user'], 'password' => config['cinematik']['password'],
                         'submit' => 'Log in!', 'returnto' => '/' }

client.post("http://cinematik.net/takelogin.php", cinematikLoginParams)

# login to torrentleech.org

puts "Logging to torrentleech.org as `#{config['torrentleech']['user']}` .."
torrentleechLoginParams = { 'username' => config['torrentleech']['user'], 'password' => config['torrentleech']['password'],
                         'login' => 'submit' }

client.post("http://torrentleech.org/user/account/login/", torrentleechLoginParams)


# walk trakt collection and get hdbits results
puts "Scanning hdbits.org for watchlisted movies (#{trakt_collection.size}) .."

output = []
output_html = ["<html><head><meta charset='utf-8'></head><body><script src='moment.min.js'></script><script> document.getElementById('timeelapsed').appendChild(document.createTextNode(moment('Time.now').fromNow())); </script>
<link type='text/css' rel='stylesheet' href='style.css'>
Generated: #{Time.now} [<span id='timeelapsed'></span>]<br /><br /><table>"]

# (<a href='update.php'>update</a>)

trakt_collection.each do |item|

  next if item.empty?

  out = { 'name' => item['title'], 'imdb_id' => item['imdb_id'], 'results' => [] }
  next if (!item['imdb_id'] || item['imdb_id'].empty?)

  p out['name'] 

  params = { 'searchtype' => 'classic', 'imdb' => item['imdb_id'].gsub!('tt',''), 
             'filmexpand' => 1 }
  res_hdbits = JSON.parse client.post("https://hdbits.org/ajax/search.php", params).body
  res_cinematik = cinematik_search(client, item['imdb_id'])
  res_torrentleech = torrentleech_search(client, item['title'], item['imdb_id'])

  #p res_cinematik
  #p res_hdbits
  p res_torrentleech

  res = res_hdbits['results'] + res_cinematik + res_torrentleech

  output_html << "<tr class='#{ res.size > 0 ? "good" : ""}'><td><img src='#{item["images"]["poster"].gsub(/\.jpg/,"-138.jpg")}' width='100'></td><td valign='top'><a href='#{item["url"]}'><b>#{item["title"]}</b></a> (#{item["year"]})</td><td valign='top'>"
  res.each do |r|
    obj = { 'id' => r['id'], 'name' => r['name'], 
            'type' => (r.include?('type') ? r['type'] : 'hdbits'),
            'url' => (r.include?('type') ? url(r['type'], r['id']) : url("hdbits", r['id']) ),
            'freeleech' => (r.include?('freeleech') ? (r['freeleech']=='yes') : false)
    }

    out['results'] << obj
    p obj['url']
    output_html << "[#{obj['type']}] <a href='#{obj['url']}' class='#{obj['freeleech'] ? 'freeleech' : ''}'>#{obj['name']}</a><br />"
  end
  putc "."
  sleep 0.01

  output_html << "</td></tr>"
  output << out
end


puts " ok"
output_html << "</table></body></html>"

puts "Saving to `output.json` .."
File.open('output.json', 'w') { |f| f.write(JSON.dump(output)) }

puts "Saving to `index.html` .."
File.open('index.html', 'w') { |f| f.write(output_html.join("\n")) }

puts "Done."
