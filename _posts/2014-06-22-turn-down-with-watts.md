---
layout: post
title: 'Turn Down with Watts'
date: 2014-06-22 16:59:03
tags:
- 'Hacks'
- 'Ruby'
permalink: /turn-down-with-watts/
---
_In which I wire up Twilio to my lights, in an effort to appease my neighbors…_

---

I am a drummer, the noise-polluting bane of apartment dwellers everywhere. In an effort to find some sort of balance (_read: not get kicked out of the complex_), I picked up one of these so that I can shunt most of that noise into my headphones:

![Roland V-Drums](/assets/images/vdrums.jpg)

Turns out though, if you hit a piece of plastic with a stick hard enough, it still makes a non-trivial amount of sound. To make matters worse, you _have_ to wear headphones if you want your drums to sound like drums and not sticks-hitting-bits-of-plastic … so I'd be completely oblivious if my neighbors called or started banging on a wall to complain about all the racket.

This is the point where a reasonable man would just go talk to his neighbors and hash out a compromise.

I, however, am not a reasonable man.

# Overengineering a Solution

I've had a set of [Philips Hue bulbs](http://meethue.com/) ever since seeing them at a previous ATLRUG meetup<sup> <a href="#fn1" id="ref1">1</a></sup>. So here's the idea: spin up a Rails app on [Heroku](http://heroku.com) and integrate with [Twilio](https://www.twilio.com/) and the [Hue API](http://developers.meethue.com/) so that people can text a number to turn my lights red and I'll know to stop. 'Tis a gift to be simple.

The full app is [on Github](https://github.com/jamesdabbs/aziz), but here are the interesting bits:

## How Many Developers Does It Take …

The Hue bulbs have a [fairly well documented API](http://developers.meethue.com/) and there are some [gems](https://github.com/soffes/hue) available. Unfortunately those are primarily focused on interacting with a set of bulbs on your local network, which won't cut it if we want to toggle the bulbs from Heroku. Fortunately, I know that e.g. the official Hue app can reach the bridge from an external network, so this must be possible …

Turns out it's actually not too painful. The tricky part is getting an access token, and the trick to that is [essentially pretending to be e.g. an iPhone app trying to register](http://blog.paulshi.me/technical/2013/11/27/Philips-Hue-Remote-API-Explained.html).

Once you've got your access token, using it is quite straightforward:

```ruby
class Light
  include HTTParty
  base_uri "https://www.meethue.com/api"
  default_params token: ENV.fetch("HUE_ACCESS_TOKEN")

  def self.alert!
    call "PUT", "groups/0/action", '{"on":true, "sat":255, "hue":0}'
  end

  private

  def self.call method, endpoint, message
    clip = %|clipmessage={
      bridgeId: "#{ENV.fetch 'HUE_BRIDGE_ID'}",
      clipCommand: {
        url: "/api/0/#{endpoint}",
        method: "#{method}",
        body: #{message}
      }
    }|

    post "/sendmessage", body: clip.squish, verify: false
  end
end
```

Since this app is public / hosted on Heroku, I'm using `ENV` variables to store sensitive information and [dotenv](https://github.com/bkeepers/dotenv) to manage those locally.

The `clipmessage` / `sendmessage` business is essentially just a way to wrap up a regular API call and execute it remotely. In my case, I've already set up and hardcoded a group (`/groups/0`) consisting of the bulbs downstairs by the drums. With that in place, turning on the red light is just a matter of setting a few attributes on that group: `{"on": true, "sat": 255, "hue": 0}`.


## Receiving Texts with Twilio

[Twilio](https://www.twilio.com/) provides several communication automation services, and I'm using their [SMS](https://www.twilio.com/sms)s. If you're playing along at home, you'll need to register a number and record your account SID and auth token, as well as getting a few credits for your account ($1/mo per number plus &#162;&#190; per text). From there, the [twilio-ruby gem](https://github.com/twilio/twilio-ruby) makes things fairly simple.

First, we need to route incoming texts to an action like

```ruby
class MessagesController < ApplicationController
  # Requests should be cross-site, so disable CSRF
  skip_before_filter :verify_authenticity_token

  def create
    # Make sure we only respond to requests actually
    # coming from Twilio
    if params[:AccountSid] != ENV.fetch("TWILIO_ACCOUNT_SID")
      raise "Unexpected message sender"
    end

    message = Message.create!(
      from: params[:From],
      body: params[:Body]
    )
    
    Light.alert!

    message.reply "Roger! Keeping it down momentarily…"

    # Twilio doesn't much care about what we send back
    # but we don't want to 500 on failing to render
    # a template
    head :no_content
  end
end
```

`Message` here is just an `ActiveRecord` which saves incoming messages and allows us to reply to them like so:

```ruby
class Message < ActiveRecord::Base
  def reply text
    twilio.messages.create(
      from: ENV.fetch("TWILIO_NUMBER"),
      to:   self.from,
      body: text
    )
  end

  private

  def twilio
    @_twilio ||= Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    ).account
  end
end
```

The full app has some other features - [error monitoring](https://github.com/jamesdabbs/aziz/blob/87982c526c0f273d999eb9544d3ab052c60d9d62/config/initializers/rollbar.rb), [email notifications](https://github.com/jamesdabbs/aziz/blob/87982c526c0f273d999eb9544d3ab052c60d9d62/app/models/imposition.rb#L15), and [a traditional form input](https://github.com/jamesdabbs/aziz/blob/87982c526c0f273d999eb9544d3ab052c60d9d62/app/views/impositions/new.html.slim) ... but that's the MVP.

# Living With It

I've had an earlier version of this app "in production" for several months now, and it has been used in earnest exactly zero times. Turns out the walls are pretty thick, and my neighbors are pretty cool. Also, people are quite a/bemused when you tell them about a project like this, which garners some goodwill. But hey, now I can do this:

![Aziz! ... Lights!](/assets/images/drum-lights.gif)

Rock on.

_A request: in the spirit of civility, please don't find and abuse the Heroku app. I'd just as soon not have to implement an IP whitelist._

---

<sup id="fn1">1) http://atlrug.com but the specific talk seems to predate the archives and my recollection is hazy, unfortunately.<a href="#ref1">↩</a></sup>
