require 'rubygems'
require 'bundler/setup'
require 'httparty'
require 'multi_json'
require 'rufus-scheduler'
require 'pry'

SCHEDULER = Rufus::Scheduler.start_new

module PingdomPi
	class Monitor
		def initialize(auth = {}, options = {})
			@client = Client.new(auth)
			@options = options
			@file_path = File.expand_path(@options[:file])
		end

		def checks
			p "Fetching checks"
			checks = @client.checks
			if !checks.empty?
				handle_checks(checks)
			else
				p "No data"
			end
		end

		def handle_checks(checks)
			p "Handling check data"
			status = checks.map { |c| c[:status] }
			response_times = checks.map { |c| c[:lastresponsetime] }
			
			if status.include? "down"
				notify @options[:response_time].last[:colour]
			else
				highest_response_time = response_times.map(&:to_i).sort.last
				response = @options[:response_time].select { |rt| rt[:range].include? highest_response_time }.last				
				notify(response[:colour])
			end
		end

		def notify(colour = "000")
			p "Notifying #{colour}"
			File.open(@file_path, "w") { |f| f.write(colour) }
			p "Colour written to #{path}"
		end
	end

	class Client
		include HTTParty
		base_uri 'https://api.pingdom.com/api/2.0'
		headers "Content-Type" => "application/json"

		def initialize(auth = {})
			self.class.headers "App-Key" => auth.delete(:api_key)
			@auth = auth
		end

		def checks(opts = {})
			opts.merge!({ basic_auth: @auth })
			response = self.class.get("/checks", opts)
			if response.success?
				parse_response(response.body)[:checks]
			else
				response
			end
		end

		private
		def parse_response(body)
			MultiJson.load(body, symbolize_keys: true)
		end
	end
end

monitor = PingdomPi::Monitor.new({
	username: ENV['PINGDOM_USERNAME'],
	password: ENV['PINGDOM_PASSWORD'],
	api_key: ENV['PINGDOM_API_KEY']
}, {
	response_time: [
		{ range: 1...700, colour: "020" },
		{ range: 700...1500, colour: "010" },
		{ range: 1500...5000, colour: "220" },
		{ range: 5000..100000, colour: "200" }
	],
	file: "/dev/ledborg"
})

SCHEDULER.every '1m' do
	p "Performing check"
	monitor.checks
end

SCHEDULER.join
