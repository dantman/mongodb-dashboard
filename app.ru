
require 'rubygems'
gem 'mongo'
require 'mongo'

require 'yaml'
require 'erb'
require 'net/http'

def to_web(host)
	x = host.split ":"
	x[1] = (!x[1].nil? ? x[1].to_i : 27017) + 1000
	"/rest/#{x.join ":"}"
end

def h(a)
	ERB::Util.h(a)
end

app = proc do |env|
	req = Rack::Request.new env
	res = Rack::Response.new
	begin
		case req.path_info
		when "/"
			config = YAML.load(File.open("./config.yml", "r").read)
			
			title = "MongoDB Dashboard"
			body = ""
			config["mongos"].each { |mongos|
				name = mongos
				begin
					db = Mongo::Connection.from_uri(mongos).db("admin")
					mongos_online = true
				
					shards = db.command({ "listshards" => 1 })["shards"]
				
					shards.each { |shard|
						shard["url"] = "mongodb://#{shard["host"].sub(/.*\//, '')}"
						begin
							shard_db = Mongo::Connection.from_uri(shard["url"]).db("admin")
							shard["online"] = true
						
							shard["replset"] = shard_db.command({ "replSetGetStatus" => 1 })["members"]
						
						rescue Mongo::ConnectionFailure
							shard["online"] = false
						end
					}
				
				rescue Mongo::ConnectionFailure
					mongos_online = false
				end
				body << (ERB.new(File.open("./mongos.erb", "r").read).result binding)
			}
			res.write(ERB.new(File.open("./layout.erb", "r").read).result binding)
			res.header["Content-Type"] = "text/html; charset=UTF-8"
		when "/style.css"
			res.header["Content-Type"] = "text/css; charset=UTF-8"
			res.write(File.open("./style.css", "r").read)
		when /^\/rest\/(.+?)(?:\/(.*))?$/
			return [500, {}, ["Only GET is implemented."]] unless req.request_method == "GET"
			base = $1
			url = URI.parse("http://#{$1}/#{$2}")
			http_req = Net::HTTP::Get.new(url.path)
			http_res = Net::HTTP.start(url.host, url.port) { |http| http.request(http_req) }
			res.status = http_res.code
			body = http_res.body.gsub /href="\/(.*?)"/ do |m|
				%Q[href="/rest/#{base}/#{$1}"]
			end
			res.write body
		else
			res.status = 404
			res.write "Not Found"
		end
	rescue => e
		res.status = 500
		res.header["Content-Type"] = "text/plain; charset=UTF-8"
		res.write e.message
		res.write "\n----\n"
		res.write e.backtrace.join("\n")
	end
	res.finish
end


run app

