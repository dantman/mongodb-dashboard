
require 'rubygems'
gem 'mongo'
require 'mongo'

require 'yaml'
require 'erb'
require 'net/http'
require 'coderay'

def to_web(host)
	x = host.split ":"
	x[1] = (!x[1].nil? ? x[1].to_i : 27017) + 1000
	"/rest/#{x.join ":"}"
end

def h(a)
	ERB::Util.h(a)
end

config = YAML.load(File.open("./config.yml", "r").read)
app = proc do |env|
	req = Rack::Request.new env
	res = Rack::Response.new
	
	case req.path_info
	when "/"
		config = YAML.load(File.open("./config.yml", "r").read)
		
		title = "MongoDB Dashboard"
		body = ""
		mongos_i = 0
		config["mongos"].each { |mongos|
			mongos_i += 1
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
			http_res.each_header { |key, value| res.header[key] = value }
			body = http_res.body
			case http_res.content_type
			when /application\/json/
				res.header["Content-Type"] = "text/html; charset=UTF-8"
				# If rhino and js-beautify are present use them to clean up the data before highlighting
				if config["rhino"]
					require 'tempfile'
					tmpfile = Tempfile.new("jsonreq#{(rand()*100000000000000).to_i.to_s(16)}")
					tmpfile.write body
					tmpfile.close
					body = `cd js-beautify/; java -jar #{File.expand_path(config["rhino"])} beautify-cl.js #{File.expand_path(tmpfile.path)}`
					tmpfile.unlink
				end
				body = CodeRay.scan(body, :js).div
			when /text\/html/, nil, ""
				body = body.gsub /href="\/(.*?)"/ do |m|
					%Q[href="/rest/#{base}/#{$1}"]
				end
			end
			body << (ERB.new(File.open("./mongos.erb", "r").read).result binding)
		}
		res.write(ERB.new(File.open("./layout.erb", "r").read).result binding)
		res.header["Content-Type"] = "text/html; charset=UTF-8"
	when "/style.css"
		res.header["Content-Type"] = "text/css; charset=UTF-8"
		res.write(File.open("./style.css", "r").read)
	when /^\/step_down\/([-_.:a-z0-9]+:\d+)$/
		db = Mongo::Connection.from_uri("mongodb://#{$1}").db("admin")
		db.command({ "replSetStepDown" => true })
		res.redirect(req.url.sub(/^([a-z]+:\/\/.+?)(\/.*)$/, "\\1"), 303)
	else
		res.status = 404
		res.write "Not Found"
	end
	res.finish
end


run app

