---
layout: post
title: 'Introducing: Droxy'
permalink: /introducing-droxy/
---

_Nods to [Foxy Shazam](https://www.youtube.com/watch?v=nWiNN_pA9cA) for the title and development soundtrack_

This morning, I realized I was tired of typing `docker-machine ip $FOO`. So I wrote [a thing](https://github.com/jamesdabbs/droxy) to route requests to `http://$NAME.dock:$PORT` on to the [docker-machine](https://docs.docker.com/machine/) running at `docker-machine ip $NAME`.

Sitting here atop my pile of yak hair, I'd like to a take a minute to reflect on what I built and - more importantly - what I learned along the way. I've long been intrigued by [Pow](pow.cx) and know that I learn with my hands, so digging in and building something similar sounded exciting. Here's what I found:

<!--more-->

![Automation](https://imgs.xkcd.com/comics/automation.png)

## How Pow Works

If you're not familiar with [Pow](http://pow.cx/) it's a "zero-config Rack server for OSX". The idea is that you register `your-app` with Pow (by simply creating a symlink `~/.pow/your-app => /path/to/your-app`), and then Pow will listen for requests to `your-app.dev`, `rackup` if needed, and forward the request on. No muss, no fuss, no forgetting to start servers or mucking around with ports. It all (modulo `pry` - sad face emoji) Just Works™.

That's left me with the same question as anything else comparably magical: how does it just works? Fortunately, Pow has [well-annotated source code](http://pow.cx/docs/) available - though, interestingly enough for a Rack server server, it's written in coffeescript. Here are the key (for me) parts -

### /etc/resolver/dev

Pow [writes](https://github.com/basecamp/pow/blob/163f546854b833bd8bb097cf9bad5be8420da727/src/installer.coffee#L88) something like the following to `/etc/resolver/dev`:

    # Lovingly generated by Pow
    nameserver 127.0.0.1
    port 20560

This hooks into [OSX's resolver system](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man5/resolver.5.html) and makes sure that DNS requests for the `.dev` TLD are routed to port 20560 (by default; most of this is configurable), where ...

### DNS server

Pow also [starts](https://github.com/basecamp/pow/blob/163f546854b833bd8bb097cf9bad5be8420da727/src/daemon.coffee#L81) a [DNS server](http://pow.cx/docs/dns_server.html). This server is quite simple - it resolves all requests for a `.dev` domain to 127.0.0.1.

### Firewall rule

Now we have a problem - we'll be getting a lot of `.dev` traffic to localhost port 80 (the default HTTP port) but don't _really_ want to run pow with enough privileges to bind port 80. So Pow also [adds](https://github.com/basecamp/pow/blob/163f546854b833bd8bb097cf9bad5be8420da727/src/installer.coffee#L16) a [firewall rule](https://github.com/basecamp/pow/blob/163f546854b833bd8bb097cf9bad5be8420da727/src/templates/installer/cx.pow.powd.plist.eco) to route that traffic to port 20559 (again, by default), where ...

### HTTP server

Pow is also running a [web server](http://pow.cx/docs/http_server.html). This is where the bulk of the business logic is, but it's also slightly more familiar territory - a middleware stack responsible for `find[ing]RackApplication`s, `handl[ing]ProxyRequest`s and so on.

### Others

There's lots more good stuff in the config layout and installer script and update strategy, that I'd feel remiss not to mention. That said, it's a bit out of scope for this post.


## How DNS Works

Potentially embarrassing confession: before this morning, I could sum up what I knew about DNS as

* It's like a phonebook for the internet (name => ip)
* I have to set up A records to get my domains pointed to the right place
* There are namesevers in the mix somewhere

so this seemed like a nice chance to get a little more familiar with the process. I pretty quickly stumbled upon [`dig`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/dig.1.html) which proved invaluable for tracing DNS lookups. For example, `$ dig google.com` produces

    ; <<>> DiG 9.8.3-P1 <<>> google.com
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 28324
    ;; flags: qr rd ra; QUERY: 1, ANSWER: 8, AUTHORITY: 0, ADDITIONAL: 0

    ;; QUESTION SECTION:
    ;google.com.                    IN      A

    ;; ANSWER SECTION:
    google.com.             242     IN      A       65.199.32.25
    google.com.             242     IN      A       65.199.32.24
    google.com.             242     IN      A       65.199.32.27
    google.com.             242     IN      A       65.199.32.26
    google.com.             242     IN      A       65.199.32.21
    google.com.             242     IN      A       65.199.32.20
    google.com.             242     IN      A       65.199.32.23
    google.com.             242     IN      A       65.199.32.22

    ;; Query time: 17 msec
    ;; SERVER: 192.168.1.1#53(192.168.1.1)
    ;; WHEN: Wed Sep  2 21:36:21 2015
    ;; MSG SIZE  rcvd: 156

showing that a query for `google.com` could resolve to any of the listed ips.

So - new sledgehammer in hand - I spun up a simple [RubyDNS server](https://github.com/ioquatix/rubydns), plopped a couple `pry`s in, and started taking swings at it, first with `dig @localhost -p $PORT`, and then using an `/etc/resolver/dock` and `curl` &/or Chrome. A few searches - like [https://65.199.32.25/search?q=a+record+vs+aaaa+record](https://65.199.32.25/search?q=a+record+vs+aaaa+record) _(spoiler alert: IPv4 vs IPv6)_ - later, [here's where I ended up](https://github.com/jamesdabbs/droxy/blob/2c37fa4bee5e94abb1435dc67eabd521cc3f8569/lib/droxy/dns_server.rb#L19).

One big lesson learned: DNS lookups get cached all over the place. When something seems to be going sideways, make sure you've flushed the cache. [The specifics vary](https://support.apple.com/en-us/HT202516), but if you find yourself doing it often [make it convenient for yourself](https://github.com/jamesdabbs/.rc/blob/master/templates/zsh_aliases#L73). Also, there are wealth of chrome tools like [chrome://net-internals/#dns](chrome://net-internals/#dns) that can make your life easier.


## Future Work

I've got a workable version that I'm proud of for today, but also have a jumping-off point for a few other items I'm interested in.

### Web Server

One of the nice things about Pow is that all your `*.dev` requests pass through the webserver, so you have a good opportunity to present well-formed error messages ("`rackup` failed to start", "something's wrong with `rvm`", &c.). I'd love to be able to present similar messages - i.e. to distinguish between "this is a valid machine that is running", "this is running, but nothing is responding on the given port" and "that isn't even a Docker machine, what are you talking about?".

That will require rethinking the architecture a bit, however. Droxy may get requests for any arbitrary ports on the Docker machine, and we can't listen on all of them. We could change the syntax - requesting `4567.dev.dock`, for instance - or try to get smart about running containers and do something like `sinatra.dev.dock`. If you have ideas here, please [let me know](mailto:jamesdabbs@gmail.com)!

### Celluloid

RubyDNS is in the process of being re-written as a thin layer over [`Celluloid::DNS`](https://github.com/celluloid/celluloid-dns). I've been intrigued by [Celluloid](https://github.com/celluloid/celluloid) ever since doing [a deep-dive into Sidekiq's architecture](https://www.youtube.com/watch?v=_8X96hMaRXI), and would love to port this over to sit directly on top of Celluloid and make more extensive use of it. The [ip lookup cache](https://github.com/jamesdabbs/droxy/blob/2c37fa4bee5e94abb1435dc67eabd521cc3f8569/lib/droxy.rb#L18), for instance, would be a natural fit for an actor that could poll periodically in the background for improved (perceived) performance.


## Takeaways

To me, programming is a weird mix between being delighted when things work magically, and wanting to eliminate all magic. This morning, Pow and DNS were magic; tonight, not so much.

I'm also a big believer in learning by doing. For me, this sort of rolling-up-your-sleeves and reverse engineering is infinitely more illuminating than reading a textbook or Wikipedia article or blog post (sorry). Now I've got a skeleton to start learning more about ["what happens when I type 'google.com' and press enter"](https://github.com/alex/what-happens-when) interview questions.

So next time you run across a yak, shave away. You never know what you'll find under it all.

And I'll get back to Dockerizing my Haskell environment tomorrow, I promise.
