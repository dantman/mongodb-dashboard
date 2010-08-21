
require 'rubygems'
gem 'mongo'
require 'mongo'

require 'yaml'
require 'erb'

def to_web(host)
	x = host.split ":"
	x[1] = x[1].to_i + 1000
	x.join ":"
end

app = proc do |env|
	req = Rack::Request.new env
	res = Rack::Response.new
	
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
	else
		res.status = 404
		res.write "Not Found"
	end
	
	res.finish
end


run app

