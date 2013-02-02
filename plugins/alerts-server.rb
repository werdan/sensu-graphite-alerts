#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'
require 'amqp'
require 'net/http'
require 'logger'


#Todo - correct stop and rabbitmq.close
#Still queue.subscribe fetch all the messages in queue
#expect one by one fetch

  class Notificator

    GRAPHITE_HOST = "127.0.0.1"
    GRAPHITE_PORT = "80"
    LOG_FILE = "/var/log/sensu/alerts-server.log"

    def initialize(options={})
      log_file = File.new(LOG_FILE, 'a')
      log_file.sync = true
      @logger = Logger.new(log_file,"daily")
      $stderr = log_file
      @logger.level = Logger::DEBUG

      config_contents = File.open("/etc/sensu/config.json", 'r').read
      @settings =JSON.parse(config_contents, :symbolize_names => true)
      @timers = Array.new
      @checks_in_progress = Array.new
    end

    def start
      trap_signals
      @logger.debug("connecting to rabbitmq: #{JSON.pretty_generate(@settings[:rabbitmq])}")      
      connection_failure = Proc.new do
        @logger.fatal("cannot connect to rabbitmq")
        exit 2
      end
        @rabbitmq = AMQP.start(@settings[:rabbitmq], {
          :on_tcp_connection_failure => connection_failure,
          :on_possible_authentication_failure => connection_failure
        }) do |connection, open_ok|
          connection.on_tcp_connection_loss do |conn, settings|
            @logger.warn("Network failure, reconnecting...")
            conn.reconnect(false, 5)
          end
          @amq = AMQP::Channel.new(@rabbitmq)
          @amq.prefetch(1)
          @amq.auto_recovery = true
          @queue = @amq.queue("notifications_checks", :auto_delete => false).subscribe(:ack => true) do |header, body|
            begin
              @logger.debug("Received event: #{body}")
              check = JSON.parse(body, :symbolize_names => true)
              execute_check(check)
              header.ack
            rescue JSON::ParserError => error
              @logger.warn("Check can not be parsed")
            end
          end
        end
    end

    def publish_result(options = {})      
      check = {
        :issued => Time.now.to_i,
        :duration => 0,
        :status => 0,
        :handlers => ["mailer"]  
      }

      client = options[:hostname]
      options.delete(:hostname)

      payload = {
        :client => client,
        :check => check.merge(options)
      }
      @logger.info("publishing check result: #{JSON.pretty_generate(payload)}")
      @amq.queue('results').publish(payload.to_json)
    end

    def execute_check(check)
      @logger.debug("attempting to execute check: JSON.pretty_generate(check)}")
      graphite_response = get_metric(check[:metric], check[:from])
      current_value = graphite_response.last['datapoints'].last.first
      if threshold_crossed?(check, current_value)
        publish_result(
          :hostname => check[:hostname],
          :email => check[:email],
          :status => 2, 
          :subject => check[:subject], 
          :output => check[:description],
          :name => check[:name])
      else
        publish_result(
          :hostname => check[:hostname],
          :email => check[:email],
          :status => 0, 
          :name => check[:name])
      end

    end

    def threshold_crossed?(check, current_value)
      return false unless current_value && check && threshold = check[:threshold].to_f

      case check[:comparator]
        when "gt"
          current_value > threshold
        when "gte"
          current_value >= threshold
        when "lt"
          current_value < threshold
        when "lte"
          current_value <= threshold
        else 
          false
      end
    end

    def stop
      @logger.warn('stopping')
      @timers.each do |timer|
        timer.cancel
      end
      unsubscribe do
        @logger.warn('stopping reactor')
        EM::stop_event_loop
      end
    end

    def unsubscribe(&block)
      @logger.warn('unsubscribing from client subscriptions')
      @queue.unsubscribe
      block.call
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          @logger.warn("received signal #{signal}")
          stop
        end
      end
    end

  def get_metric(target, from = "-1hour")
    http = Net::HTTP.new(GRAPHITE_HOST,GRAPHITE_PORT)
    req = Net::HTTP::Get.new("/render?target=keepLastValue(#{target})&format=json&from=#{from}")
    res = http.request(req)
    case res.code
      when "200"
        JSON.parse(res.body)
      else
        @logger.error("Unexpected HTTP response code from Graphite:#{res.code}")
    end
  end
end

notificator = Notificator.new
notificator.start
