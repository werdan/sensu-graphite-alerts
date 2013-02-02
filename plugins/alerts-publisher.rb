#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'sensu-plugin/utils'
require 'json'
require 'amqp'

class NotificatorPublisher < Sensu::Plugin::Check::CLI

  include Sensu::Plugin::Utils
      
	def run
    alerts = settings["alerts"]

    connection_failure = Proc.new do
      puts "Can not connect to RabbitMQ server"
      exit 2
    end

    #http://stackoverflow.com/questions/800122/best-way-to-convert-strings-to-symbols-in-hash
    AMQP.start(settings["rabbitmq"].inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}, {
        :on_tcp_connection_failure => connection_failure,
        :on_possible_authentication_failure => connection_failure
      }) do |connection, open_ok|
      AMQP::Channel.new do |channel, open_ok|
        AMQP::Queue.new(channel, "notifications_checks", :auto_delete => false) do |queue, declare_ok|
          alerts.each do |alert|
            queue.publish(alert.to_json)
          end
          connection.close {
            EM.stop { exit }
          }
        end
      end
    end
    ok
  end

end