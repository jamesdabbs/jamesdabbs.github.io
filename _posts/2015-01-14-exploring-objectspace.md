---
layout: post
title: 'Exploring ObjectSpace'
date: 2015-01-14 04:03:39
tags:
- 'test'
- 'thing'
- 'Thing with spaces in it'
image: /assets/images/mbp2.jpg
---
I recently had a very interesting conversation with [Chris Hoffman](https://twitter.com/yarmiganosca) at [DCRUG](http://www.meetup.com/dcruby), talking about how to explore the object graph of a highly complex Rails app. I've been mulling over some of his ideas and found myself with a few hours to kill on a flight from Austin, so I dug in and did the following rather enjoyable bit of spelunking. 

Here's what I want -

* A view of the ancestry lattice of each class
* A view of the `(has|belongs_to)_(many|one)` relationships of reach class
* A (summary) view of the message flow between instances of each class

preferably with some option for filtering down to only classes "of interest" (i.e. defined in this particular app, or not defined in Rails or something).

Ultimately, I'd _love_ to produce a gem from this which mounts as a Rails engine exposing a rich D3 visualization of all those graphs. But it's a short flight, so let's start by proving the concept and make sure we have access to the data we need.

# Ancestry

First up: be able to summarize the lineage of each model (e.g. what they subclass / include, and from where).

**TL;DR** - The magic is `Rails::Engine.eager_load!`, [`ObjectSpace#each_object`](http://www.ruby-doc.org/core-2.2.0/ObjectSpace.html#method-c-each_object), [`Module#ancestors`](http://www.ruby-doc.org/core-2.2.0/Module.html#method-i-ancestors) and [`Module#parent`](http://apidock.com/rails/ActiveSupport/CoreExtensions/Module/parent)

```ruby
# In e.g. `config/initializers/tycho.rb`
module Tycho # don't sully up the global namespace
  class << self
  
    def each_subclass klass
      ObjectSpace.each_object(Class).select { |k| k < klass }
    end

    def models
      # In development by default, classes are only loaded as needed
      # and so won't be in ObjectSpace, so we force loading them
      each_subclass(Rails::Application).each &:eager_load!
      each_subclass ActiveRecord::Base
    end

    def lineage mod
      mod.ancestors.group_by(&:parent).map do |parent, subs|
        [parent, subs.select { |sub| noteworthy? sub }]
      end.to_h
    end

    def noteworthy? mod
      # This is rather ad-hoc, but it's safe to assume these
      # are always present
      return false if [Object, Kernel, BasicObject].include? mod
      
      # There also seem to be a few of these. Not sure why;
      # this bears further investigation
      return false if mod.anonymous? && mod.instance_methods.empty?
      
      true
    end

    def userspace? mod
      # FIXME: this should be customizable, or at least smarter
      noteworthy? mod
    end
end
```

With this set up, we can drop in a [`binding.pry`](https://www.youtube.com/watch?v=D9j_Mf91M0I) at the end of this initializer and poke around. In the [test app](https://github.com/PeaceCorps/medlink) I'm working with, we get the following (_with my comments added_):

```ruby
[1] pry(main)> Tycho.models
=> [Country (call 'Country.connection' to establish a connection),
 CountrySupply (call 'CountrySupply.connection' to establish a connection),
 Order (call 'Order.connection' to establish a connection),
 Phone (call 'Phone.connection' to establish a connection),
 Request (call 'Request.connection' to establish a connection),
 Response (call 'Response.connection' to establish a connection),
 SMS (call 'SMS.connection' to establish a connection),
 Supply (call 'Supply.connection' to establish a connection),
 User (call 'User.connection' to establish a connection)]
[2] pry(main)> Tycho.lineage(Order).keys
=> [Object, # This is the "parent" for things in the top-level namespace
 ActionView::Helpers,
 ActiveRecord::AttributeMethods::Serialization,
 Order (call 'Order.connection' to establish a connection),
 Concerns, # Our app's model concerns
 Kaminari,
 ActiveRecord,
 CanCan,
 ActiveModel::Serializers,
 ActiveModel,
 ActiveModel::Validations,
 ActiveRecord::AttributeMethods,
 ActiveRecord::Locking,
 ActiveSupport,
 ActiveRecord::Scoping,
 PP, # Probably mixed in via pry?
 ActiveSupport::Dependencies,
 JSON::Ext::Generator::GeneratorMethods]
```

And moreover

```ruby
[1] pry(main)> Tycho.lineage(Order)[ActiveRecord]
=> [ActiveRecord::Base,
 ActiveRecord::Store,
 ActiveRecord::Serialization,
 ActiveRecord::Reflection,
 ActiveRecord::Transactions,
 ActiveRecord::Aggregations,
 ActiveRecord::NestedAttributes,
 ActiveRecord::AutosaveAssociation,
 ActiveRecord::Associations,
 ActiveRecord::Timestamp,
 ActiveRecord::Callbacks,
 ActiveRecord::AttributeMethods,
 ActiveRecord::CounterCache,
 ActiveRecord::Validations,
 ActiveRecord::Integration,
 ActiveRecord::AttributeAssignment,
 ActiveRecord::Sanitization,
 ActiveRecord::Scoping,
 ActiveRecord::Inheritance,
 ActiveRecord::ModelSchema,
 ActiveRecord::ReadonlyAttributes,
 ActiveRecord::NoTouching, # So glad this exists
 ActiveRecord::Persistence,
 ActiveRecord::Core]
```

# Relations

This ended up being surprisingly easy to get the basics going, since Rails tracks so much reflective information about relations _[Ed: though, as [JD Isaacks](https://twitter.com/jisaacks) was so kind as to point out, it probably [misses some edges](https://github.com/jamesdabbs/tycho/issues/1)]_:

```ruby
module Tycho
  def self.relations mod
    mod.reflections.each_with_object({}) do |(name, ref), h|
      h[ref.macro] ||= []
      h[ref.macro] << name.to_s.classify.constantize
    end
  end
end
```

Which produces something like:

```ruby
[1] pry(main)> Tycho.relations Request
=> {:belongs_to=>
  [User (call 'User.connection' to establish a connection),
   Country (call 'Country.connection' to establish a connection)],
 :has_many=>[Order (call 'Order.connection' to establish a connection)]}
```

# Tracing Messages

The ultimate goal here is to record and summarize each message passed to or from (some subset of) objects in your app. Unsurprisingly, this is probably the hardest of the three goals above. A few considerations come to mind:

* This is almost certainly a use case for the new-ish [TracePoint API](https://vaskoz.wordpress.com/2014/03/01/ruby-2-1-tracepoint-api/)
* We'll want to be able to monitor message flow in a few contexts, like during testing, or while playing back recorded production traffic
* This is likely heavy-weight enough that we want some way to turn it off and on (by e.g. sending signals to a running server process)

There's certainly more iteration to be done on this point, but here's a rough proof-of-concept that logs each message to a tempfile for retrieval later -

```ruby
require 'csv'

module Tycho
  @@trace_file = CSV.open "/tmp/tycho.log", "w"

  @@tracer = TracePoint.new :call do |tp|
    receiver = tp.defined_class
    next unless Tycho.userspace? receiver

    sender = tp.binding.eval 'self.class'
    next unless Tycho.userspace? sender

    entry = [sender, receiver, tp.method_id]
    begin
      @@trace_file << entry
    rescue => e
      # FIXME: Seems like some senders don't implement `to_str`
      #warn "Couldn't record #{entry} - #{e}"
    end
  end

  class << self
    def observe!
      @@trace_file.rewind
      @@tracer.enable
    end

    def report!
      @@tracer.disable
      CSV.read "/tmp/tycho.log"
    end
  end
end
  
Signal.trap "USR1" do
  warn "Starting trace (got USR1)"
  Tycho.observe!
end

Signal.trap "USR2" do
  warn "Stopping trace (got USR2)"
  Tycho.report!
end
```

We can try this out by spinning up a `rails s`, doing `ps aux | grep rails` to note the pid, `kill -USR1 <pid>` to start recording, poke around the local server a bit, then `kill -USR2 <pid>` to stop logging (or just `tail -f /tmp/tycho.log` as the log updates).

# Future Work

I've started [a repository](https://github.com/jamesdabbs/tycho) for this project and will work on making it more robust and adding more usable visualizations of these several graphs. This is definitely a low priority project at the moment though, so if it's something you'd be interested in using seriously, please [let me know](https://twitter.com/jamesdabbs) - I'd love to have some help, direction, or motivation to work on this more.
