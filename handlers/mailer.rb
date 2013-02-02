#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'

class Mailer < Sensu::Handler

def handle
  history = event['check']['history']
  action = event['action']

  #Sends mail, only if the last check result is critical and just before that there was ok or nothing 
  if action == "create"
     history.last.to_i != 0 && 
     (history.last(2).first.to_i == 0 || history.length == 1 )

    subject = event['check']['subject']
    email = event['check']['email']
    message = event['check']['output']
    `echo "#{message}" | mail -s "#{subject}" #{email}`
  end
end  
end
