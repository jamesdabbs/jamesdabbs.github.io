---
layout: post
title: 'Announcing: TuneYard'
date: 2014-12-25 15:40:45
tags:
- 'Technical'
- 'Sonic Pi'
- 'SuperCollider'
- 'Hacks'
image: /assets/images/boop.png
permalink: /announcing-tuneyard/
---
[TuneYard](https://github.com/jamesdabbs/tune_yard) is a lightweight gem providing a [Sonic Pi](http://sonic-pi.net/) remote, and letting you embed snippets like their provided examples inside any arbitrary Ruby code. My intention is to use this to power an [upcoming Iron Yard class](http://theironyard.com/locations/washington-dc/) project that I'm particularly excited about, but [let me know](mailto:jamesdabbs@gmail.com?subject=TuneYard) if you have something else in mind; I'd love to support more general use.


Big shout outs to [Sam Aaron](http://sam.aaron.name/) for developing [Sonic Pi](http://sonic-pi.net/) and [Overtone](http://overtone.github.io/), all [the Sonic Pi contributors](https://github.com/samaaron/sonic-pi/graphs/contributors) for all their work, and [tUnE-yArDs](http://tune-yards.com/) for the naming inspiration and development soundtrack.

# Motivation

As mentioned [last time](http://jdabbs.com/to-build-a-fire/), I'm taking a bottom-up approach with my next Ruby class. Brit<sup><a href="#fn1" id="ref1">1</a></sup> and I have been batting around concepts for a large project focusing on understanding controllers, and came up with one that I can't wait to try out. The rough idea is to have students pair off and create a script-instrument to play a server-song.

There are a few things that I find really exciting about this project:

* Controllers are _really_ hard to practice with in isolation, since we often think of them as the glue that connects models and views. If we rule out rendering views, what can we do? Well, we can make sound.
* I've been listening to some [John Luther Adams](http://www.wqxr.org/#!/story/john-luther-adams-poor-career-choices-finding-home-alaska/) lately, and will be working on a piece with a nod to [The Place Where You Go to Listen](http://www.uaf.edu/museum/exhibits/galleries/the-place-where-you-go-to/), changing sounds based on data pulled from external APIs.
* Sonic Pi is an amazing project, and I'm hugely excited about the work they're doing on the educational front. I'd love to be able to contribute to that effort.
* It helps dispel that pernicious "Ruby is only good for Rails" mindset.
* It's just cool.

# Exploring Sonic Pi - An After Action Report

I was completely unfamiliar with the internals of Sonic Pi before starting on this (other than having used SuperCollider and Overtone a bit in the past). What follows was my process in exploring it. It almost certainly isn't the smartest. [Get at me](mailto:jamesdabbs@gmail.com?subject=You're an idiot&body=Here's why ...) with how you'd do better.

## Where Are We?

I started off by doing a standard OSX install of Sonic Pi from `dmg`, which installs everything to `/Applications/Sonic Pi.app`:

```bash
/Applications/Sonic Pi.app ⊩ tree -L 2
.
├── Contents
│   ├── Frameworks
│   ├── Info.plist
│   ├── MacOS
│   ├── PkgInfo
│   ├── PlugIns
│   └── Resources
├── app
│   └── server
├── etc
│   ├── doc
│   ├── examples
│   ├── samples
│   └── synthdefs
└── server -> app/server
```

A little poking through the `app` directory and I landed pretty quickly on a few items of interest: the library code in `server/sonicpi` and the scripts in `server/bin` - especially `server/bin/sonic-pi-server.rb`, which looked to be a potential entry point.

`sonic-pi-server.rb` appears to spin up an [OSC server](http://opensoundcontrol.org/introduction-osc). Fortunately, I was _somewhat_ familiar with those after [an abortive attempt](https://github.com/jamesdabbs/scruby) at getting [scruby](https://github.com/maca/scruby) up to date<sup> <a href="#fn2" id="ref2">2</a></sup>. So my rough game plan at the moment is: verify that this code is actually what's running, then try to reverse engineer the OSC messages, and write my own client to produce similar messages. That plan didn't really hold up, but it was a reasonable place to start.

## Inspect What You Expect

First things first: we need some way of inspecting code in-flight. Were this a standard command-line app, I'd [`pry`](http://pryrepl.org/) liberally, but since this is a standalone application, it's trickier. [`remote-pry`](https://github.com/Mon-Ouie/pry-remote) might be an option, but I'm not really sure how the bundled Ruby interacts with `rbenv` or where to install it, so let's start with something more basic: logging. Again, I have no idea where a `puts` would end up (if anywhere), but can rig up something:

```ruby
# In app/server/bin/sonic-pi-server.rb
def _log text
  File.open("/tmp/log", "a") { |f| f.puts text }
end
_log "Here. We. Go."
_log "Program name: #{$PROGRAM_NAME}"
_log "Path: #{__FILE__}"
```

Now we can `tail -f /tmp/log` and start up the Sonic Pi app and see:

```
Here. We. Go.
Program name: /Applications/Sonic Pi.app/Contents/MacOS/../../server/bin/sonic-pi-server.rb
Path: /Applications/Sonic Pi.app/Contents/MacOS/../../server/bin/sonic-pi-server.rb
```

So, confirmed: the app runs this script directly.

*Aside: at some point, I realized that `~/.sonic-pi/log` was a thing and started `tail`ing that as well, which was helpful but not essential.*

## Messaging

Next up, let's see what messages we're passing:

```ruby
def osc_server.dispatch_message msg
  _log "osc_server got message: #{msg.address} / #{msg.to_a}"
  super msg
end
def gui.send_raw msg
  _log "gui send_raw: #{msg}"
  super msg
end
```

*Aside: did you realize you could define methods on individual instances this way? (Hint: think about the `def self.stuff` class method pattern.)*

With that message logging in place, and after an app restart, we can poke around the GUI and see what messages are fired. Really, we want to figure out what happens when we click "play", since that's what we want to be able to replecate (but with our own Ruby injected). There are some `/load-buffer` and `/exit` calls, but the magic looks to be `/save-and-run-buffer`:

```
osc_server got message: /save-and-run-buffer / ["workspace_one", "use_arg_checks true #__nosave__ set by Qt GUI user preferences.\nuse_debug true #__nosave__ set by Qt GUI user preferences.\nloop do\n  sample :perc_bell, rate: (rrand 0.125, 1.5)\n  sleep rrand(0.1, 2)\nend", "Workspace 1"]
```

That's certainly the "song" that I'm composing in the GUI, along with some other information, so we'll investigate there further.

*Aside: as best I can tell, the `gui.send_raw` calls are just to feed results back to the GUI. We can support that guess by commenting it out and noticing that the in-GUI log doesn't update any more.*

## Eval'ing Buffers - A Closer Look

Digging into the `/save-and-run-buffer` handler, it looks like the magic is in

```ruby
sp.__spider_eval code, {workspace: workspace}
```

where `code` is the code in the window buffer (plus the `use_arg_checks` and `use_debug` lines), and `workspace` is the workspace name (a string), as we can confirm by `log_`ing. So maybe there's a more direct approach here: rather than using OSC to pass messages, maybe we can `__spider_eval` things ourselves.

Looking over the definition of `sp`, it looks like we should be able to extract the business logic to something like:

```ruby
class Player < SonicPi::Spider
  include SonicPi::SpiderAPI
  include SonicPi::Mods::Sound
end

p = Player.new "localhost", 4556, Queue.new, 5, Module.new
sleep 1 # just being defensive about race conditions
p.__spider_eval %{
use_arg_checks true #__nosave__ set by Qt GUI user preferences.
use_debug true #__nosave__ set by Qt GUI user preferences.
loop do
  sample :perc_bell, rate: (rrand 0.125, 1.5)
  sleep rrand(0.1, 2)
end
}, workspace: 'Workspace 1'
sleep 2
p.__stop_jobs
```

If we include that near the top of the server script, we get a couple pleasant chimes every time Sonic Pi boots (and an unresponsive UI because `sleep`s, but hey, it's a start).

Sure enough, once we figure out how to `require` the referenced internal Sonic Pi libraries, we should be able to extract all this to an external script. [Take a peek at the gem implementation](https://github.com/jamesdabbs/tune_yard/blob/85381af78ba085deebcfe162c260e98f190c8f95/lib/tune_yard/player.rb#L7) if you're curious about that bit.

## The Perils of Eval

So, we've got good progress (boops!), but we've got `eval` problems.

First off, we're calling `__spider_eval` with a literal string, which isn't terribly user friendly. That's an easy enough fix using [`sourcify`](https://github.com/ngty/sourcify) and some string munging.

The more confounding problem is that - unless we rewrite the Sonic Pi internals (which I have neither the clout nor wisdom to do) - we're going to call `eval(code, nil)` somewhere deep inside of `__spider_eval` (in `app/server/sonicpi/lib/sonicpi/spider.rb`) and [such an eval won't close over variables](http://www.skorks.com/2013/03/a-closure-is-not-always-a-closure-in-ruby/). So ... what can we do?

_Warning: gross hack ahead._ We want to be able to locate variables and functions that are in scope when the song block is defined, but they aren't present when we `eval` on our `Player` instance. So, let's "define" them on the player.

> Metaprogramming is like violence: if it doesn't solve your problem, you aren't using enough of it.

```ruby
class Player
  def run &block
    @_outer_block = block.binding
    __spider_eval block.to_source(strip_enclosure: true), workspace: __FILE__
  end

  def method_missing name, *args
    if @_outer_binding.local_variable_defined? name
      @_outer_binding.local_variable_get name
    else
      @_outer_binding.send name, *args
    end
  end
end
```

It's certainly not perfect (instance variables, for instance), but it's Good Enough™ for an afternoon hack - and is at least fairly simple and short.

# Result

The finished (well, not _finished_ finished, but useable) product is available on [RubyGems](http://rubygems.org/gems/tune_yard) and [Github](https://github.com/jamesdabbs/tune_yard). I'll be building on it in class and pushing improvements as I do. Let me know if you're using this for a project; I'd love to get some idea of what to support, and to have an excuse to dig into Sonic Pi further and extract out a gem properly down the road.

<sup id="fn1">1) My dear friend and colleague, who can be found [on the internet](http://blog.kingcons.io/), [the Twitter](https://twitter.com/redline6561), and [teaching Rails](http://theironyard.com/academy/rails-engineering/#class-schedule) at the Iron Yard in Atlanta.<a href="#ref1">↩</a></sup>

<sup id="fn2">2) The original [scruby](https://github.com/maca/scruby) looks pretty solid, if a bit heavy on global state and metaprogramming. Ultimately, I decided leveraging and contributing to Sonic Pi would be a better use of time.<a href="#ref2">↩</a></sup>
