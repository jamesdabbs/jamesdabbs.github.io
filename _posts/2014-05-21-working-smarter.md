---
layout: post
title: 'Working Smarter'
date: 2014-05-21 01:22:55
tags:
- 'Technical'
- 'Ruby'
---
####(In the Background)

Basic apps are often alive only inside the request-response cycle: a user asks your server for something, the server does its thing, sends back some HTML, and sits there waiting for the next user. Breaking out of that loop means one of two things, tautologically - starting before getting a request, or continuing after returning a response. The specifics vary from app to app, but there's usually quite a lot that goes on that your users really shouldn't have to wait on. I've found myself backgrounding:

* Sending emails
* Indexing documents into ElasticSearch
* Updating a Neo4j db via the REST API
* Handling expensive delete cascades or finalizing [paranoid deletes](https://github.com/radar/paranoia)
* Periodically searching for Tweets
* Processing large file uploads that could time out otherwise

Anything that communicates with an external service is a particularly good candidate - you can ensure your app responds quickly, even if theirs is slow, times out or errors. The fine folks behind Resque have some other [suggestions](https://github.com/resque/resque#jobs) - they mostly boil down to "anything that's not always super fast".

In this post, I'm mostly interested in user-triggered actions. Once you have a background system up and running, there are lots of options for triggering periodic or scheduled jobs, including [clockwork](https://github.com/tomykaira/clockwork), [rufus](https://github.com/jmettraux/rufus-scheduler) or even [cron](http://unixhelp.ed.ac.uk/CGI/man-cgi?crontab+5) if your chosen system doesn't build in what you need.

## Breaking the Cycle

The basic idea is that, rather than doing any heavy lifting in the request-response cycle, we'll simply register that we need some work done by placing a _job_ in a _queue_. Then we'll need some provision for spinning up some _workers_ to consume jobs from the queue and actually perform the work. There are a host of tools for doing this, including:

* [DelayedJob](https://github.com/collectiveidea/delayed_job)
* [Resque](https://github.com/resque/resque)
* [Sidekiq](http://sidekiq.org/)
* [SuckerPunch](https://github.com/brandonhilkert/sucker_punch)

and [many others](https://www.ruby-toolbox.com/categories/Background_Jobs). I single out these only because they are the ones I'm familiar with (although that probably roughly correlates to being popular). In choosing the one that's right for you, you'll want to at least consider the tool's architecture, coordination requirements, and built-in features. Here's a quick run-down of my experience:

### Queueing Jobs

First things first: we need to maintain our work queue(s) somewhere. Different systems take different approaches here. DelayedJob treats jobs as regular ActiveRecord objects and stores them in your database as usual. This has the benefit of being simple to get working, but can run into performance problems if you start running a sizable queue. Also - depending on your app - you may not want to persist jobs once they are done, so another data store might be more natural. [Redis](http://redis.io/) is a very popular choice, since it's often a great match on performance and persistence concerns - this is the approach taken by Resque and Sidekiq. SuckerPunch deviates a bit from the rest, but we'll get to that shortly…

### Doing Work - Threads vs. Processes

_(Warning: I may favor simplicity over technical completeness here)_

In order not to block the response, we'll have to do some multitasking, which in broad strokes means adding more threads or more processes. Parallel / concurrent programming is a huge topic that we won't cover, so here's the executive summary that you'll need for what follows: threads are lightweight workers that share memory inside a process; processes are heavier, but often more robust since they isolate memory from each other.

Your web (or DRb or whatever) server is running in a process. Most worker systems will start a separate manager process (usually with a `rake` task or something similar) that will spawn a collection of workers in either processes (DelayedJob, Resque) or threads (Sidekiq). If each worker requires a Rails app (which it usually does), that means Sidekiq can spin up a whole lot more workers with a whole lot less memory. The tradeoff there is that your code (including all of the gems that it depends on) _has_ to be threadsafe. Unless you like debugging thread race conditions (hint: you don't). [Caveat emptor](https://github.com/mperham/sidekiq/wiki/Problems-and-Troubleshooting#thread-safe-libraries).

SuckerPunch is the outlier here - it runs jobs in threads inside your server process. If you think this is brittle, you are right. So why consider it? In a word: free <a href="#note1">[1]</a>. Because it runs entirely inside one process, you can have background workers on Heroku without forking out for an extra dyno (no pun intended).

### Built-in Features

Resque and Sidekiq both ship with Rack apps to monitor the state of your jobs and workers. DelayedJob doesn't, but [there's a gem for that](https://github.com/ejschmitt/delayed_job_web) (plus with Jobs being ActiveRecords, it's not hard to access them directly). SuckerPunch has no work queue, so not much to monitor there.

Sidekiq and DelayedJobs automatically retry jobs that fail (very handy if you're hitting an external service that might be down). Resque doesn't, but [there's a gem for that](https://github.com/lantins/resque-retry).

Sidekiq and DelayedJobs also have good semantics for scheduling events, either at a fixed time or some interval from now. Resque doesn't, but [there's a gem for that](https://github.com/resque/resque-scheduler).

Here's my take-home on features: if you're trying to run on Heroku for free, use SuckerPunch; it knows its niche and nails it. Otherwise, you can gem up whatever you want, so it's a question of whether you prefer batteries included or à la carte. If you are looking for more advanced features out of the box, Sidekiq has the edge here as they sell and support [Sidekiq Pro](http://sidekiq.org/pro/) with some nice features for reliability and monitoring at large scale.

## Alright, Let's Do This…

So, you've thought about your application and its worker needs and settled on a gem. Awesome. Now what?

Now we write some code.

Stay tuned for part two, in which I'll step through the process that we decide on in [the live coding session](http://www.meetup.com/atlantaruby/events/171941842/). If you're playing along at home, feel free to fork the [app we're starting from](https://github.com/jamesdabbs/air/tree/cats) and see what you come up with. This should be good:

<a href="https://github.com/jamesdabbs/air/tree/cats">![](/content/images/2014/May/Screen-Shot-2014-05-20-at-9-38-08-PM-1.jpg)</a>

<a id="note1">[1]</a> In more words: [http://brandonhilkert.com/blog/why-i-wrote-the-sucker-punch-gem/](http://brandonhilkert.com/blog/why-i-wrote-the-sucker-punch-gem/)
