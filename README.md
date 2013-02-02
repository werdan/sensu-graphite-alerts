Sensu-Graphite-Alerts
=======================

Set of Sensu tools used to generate check results agains Graphite metrics

Motivation
-----------------------

Why do we need it? Using [Graphite](http://graphite.readthedocs.org/) one can store and analyze a huge amount of data.
At some point you may need to create multiple (ok, to put it clean dozens and dozens) of checks against data stored in Graphite.

For instance, you can have metrics organized like this:

* myserver.load_avg.*
* myserver.vmstat.*
* myserver.postfix.*

It is easy to use [Sensu-Graphite community plugin](https://github.com/sensu/sensu-community-plugins/blob/master/plugins/graphite/check-data.rb) to check that load_avg.one is in comfortable scale.
But thing get much more complicated if you have around 100 or server, each with 10-20 metrics to control.

How does it work?
-----------------------

![Diagram](https://raw.github.com/werdan/sensu-graphite-alerts/master/diagram.png)

1) alerts-publisher.rb should be added as a regular sensu check, like this:


    "alerts-publisher": {
      "command": "/etc/sensu/plugins/alerts-publisher.rb",
      "subscribers": [
        "your-sensu-server"
      ],
      "interval": 60,
      "type": "check"
    }
    
alerts-publisher reads configuration and finds section *alerts* with array of alerts defined like this:

    {
      "alerts" : 
      [
    		{
    			"name" : "apache_processes",
    			"hostname" : "myserver-node",
    			"metric" : "summarize(scale(divideSeries(maxSeries(myserver.node.apache.busy),averageSeries(myserver.node.apache.total)),100),\"5min\")",
    			"from" : "-10min",
    			"comparator" : "gt",
    			"threshold" : "20",
    			"subject" : "WARNING: High number of apache processes",
    			"description": "Server is running high number of Apache busy processes",
    			"email": "root@myproject.com"
        }
      ]
    }
    
2) This check (in JSON) goes to RabbitMQ and then is fetched by alerts-server.rb

3) alerts-server.rb can run on any host, but it was intended to be detached from alerts-publisher for two reasons:

* graphite server can be on different host
* there can be multiple graphite installations. In this case each alerst-server will query its own graphite, balancing the load on servers

4) Graphite response is compared with threshold and result is sent to sensu server

5) In case of result is in status different from 0 (ok), then mailer.rb sends a mail to *email* from alert description

It should be noted, that in order to reduce the number of mails sent, mailer.rb sends mail only if there is a switch from *ok* to *critical*.
Thus multiple critical checks results will be absorbed
