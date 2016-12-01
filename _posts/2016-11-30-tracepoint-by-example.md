---
layout: post
title: 'TracePoint by Example'
permalink: /tracepoint-by-example
tags:
- 'Technical'
- 'Ruby'
date: 2016-11-30 19:26:11
---

`TracePoint` is a uniquely powerful sledgehammer for introspecting Ruby programs. In this post, we'll take a look at what tracing can do by sketching a couple utilities.

The basic idea behind `TracePoint` is registering low-level hooks in the Ruby VM to be able to react to events throughout our program. Possible "hooks" include "every time a thread starts", "every time a block is called", "every new line" and [many more](http://ruby-doc.org/core-2.0.0/TracePoint.html#class-TracePoint-label-Events), which allow you to implement some surprisingly wide-reaching features.

I haven't profiled any of the following (but you could build a basic profiler with `TracePoint`!), and would have some concerns about over-tracing or robust error handling for production code, but these sorts of traces can be _great_ for exploring how a program executes in development, as the following examples suggest - 

# Watching for monkeypatching

Monkeypatching is the act of reopening an existing class to add your own functionality. While it's neat and can be helpful for small projects, it's [often considered a bad idea](https://www.google.com/q=monkeypatching+considered+evil) as it can cause some confusing collisions.

We can use `TracePoint`'s class-start and -end events to watch for changes in defined methods, and alert (or raise) if new methods are added -

```ruby
# Not required, but `colorize` is a nice way to prettify our
#   output. It adds e.g. `red` and `light_blue` methods to
#   String (amusingly, a monkeypatch)
require 'colorize'

module Monkeys
  Methods = {}

  # This registers a trace point hook
  # Note that this trace is _not_ active
  #   until we explicitly enable it
  Start = TracePoint.new :class do |t|
    # This hook fires any time a class or module is opened
    #   and `t.self` will be that class or module
    # Let's just focus on Classes for now
    next unless t.self.is_a?(Class)

    # Store the names of methods that the class defines
    Methods[t.self] = t.self.instance_methods
  end

  # This hook fires when a module or class hits its `end`
  #   and sets `t.self` similarly
  End = TracePoint.new :end do |t|
    next unless t.self.is_a?(Class)

    # Compare the methods that the class currently has
    #   with the ones it had when we opened it
    old     = Methods[t.self]
    current = t.self.instance_methods
    new     = current - old

    if old.any? && new.any? # Ignore the first opening
      warn "#{t.self.to_s.light_blue} has added"
      new.each do |method|
        warn " #{'*'.light_black} #{method}"
      end
      warn "#{'in'.light_black} #{t.path}:#{t.lineno}"
      warn ""
    end
  end

  # This is how we start and stop the previous hooks
  def self.watch
    Start.enable
    End.enable
  end
  def self.stop
    Start.disable
    End.disable
  end
end
```

Example useage:

```ruby
Monkeys.watch

class String
  def is_palindrome?
    self == reverse
  end
end

Monkeys.stop
```

which produces

```
String has added
 * is_palindrome?
in <file>
```


# Tracing Exception Handling

This is the example that inspired this post. I wanted to better understand where Rails' exception backtrace logging was coming from, but - unsurprisingly - the backtrace itself wasn't much help. So how do you answer a question like "where does this error go after it gets raised" in a system you're not as familiar with? Well, you can trace and examine where methods on that error object are called.

```ruby
class Trace
  class Calls
    # `item` is the object that we want to spy on
    def initialize item, methods: nil
      @values  = {}
      @files   = {}
      @callers = {}

      @trace = TracePoint.new :return do |t|
        # This hook fires every time a method returns and
        #   `t.self` is the object which defines the method
        # We only care about the item we're watching
        next unless item == t.self
        
        # We might only care about a known subset of methods
        next unless methods.nil? || methods.include?(t.method_id)

        # Record all of the return values for a given method,
        #   along with how many times the given value was
        #   returned
        @values[t.method_id] ||= {}
        @values[t.method_id][t.return_value] ||= 0
        @values[t.method_id][t.return_value]  += 1

        # We can get the binding at the point of call
        #   and use that to `eval` any expression we
        #   want.
        # In this case, we want to examine the call
        #   stack and record which files and lines
        #   show up often
        t.binding.eval('caller').each do |line|
          file = line.split(':').first
          @files[file] ||= 0
          @files[file]  += 1

          @callers[line] ||= 0
          @callers[line]  += 1
        end
      end

      @trace.enable
    end

    def disable
      @trace.disable
    end

    # Show which files contain code which call into the
    #   traced object, sorted by frequency of file
    def files
      @files.sort_by { |file, hits| -hits }.to_h
    end

    # Similarly, but by frequency of the exact call site
    #   (including line number)
    def callers
      @callers.sort_by { |file, hits| -hits }.to_h
    end

    # Which methods on this object were used (during this watch)?
    def called_methods
      @values.keys
    end

    # What values were returned by a given method (and how often)
    def values method
      @values[method]
    end
  end

  # Some utilities for starting a call trace and storing the results
  #   for later inspection
  Traces = {}

  def self.watch label, item, methods: nil
    Traces[label] = Trace::Calls.new item, methods: methods
    item
  end

  def self.stop label
    Traces.delete(label).tap(&:disable)
  end
end
```

You could use this to explore error handling in a Rails app by adding actions like

```
class MyController < ApplicationController
  def error
    raise Trace.watch "error", RuntimeError.new("whoops")
  end
  
  def inspect
    calls = Trace.stop "error"
    binding.pry # to inspect
  end
end
```

In this particular case, we see something like

```ruby
[1] pry(#<MyController>)> calls.files.first 5
=> [["/Users/james/.rbenv/versions/2.3.1/lib/ruby/gems/2.3.0/gems/actionpack-5.0.0.1/lib/action_dispatch/middleware/exception_wrapper.rb", 1816],
 ["/Users/james/.rbenv/versions/2.3.1/lib/ruby/gems/2.3.0/gems/actionpack-5.0.0.1/lib/action_dispatch/middleware/debug_exceptions.rb", 1783],
 ["/Users/james/.rbenv/versions/2.3.1/lib/ruby/gems/2.3.0/gems/railties-5.0.0.1/lib/rails/rack/logger.rb", 1074],
 ["/Users/james/.rbenv/versions/2.3.1/lib/ruby/gems/2.3.0/gems/activesupport-5.0.0.1/lib/active_support/tagged_logging.rb", 1074],
 ["/Users/james/.rbenv/versions/2.3.1/lib/ruby/gems/2.3.0/gems/puma-3.6.2/lib/puma/server.rb", 1074]]
```

and I know exactly where to go look next.

# Enforcing Idempotence

An idempotent method is one that always returns the same value, no matter how many times you call it, and is generally a Good Idea™. Referentially transparent methods have to be idempotent, and methods on value objects should generally be idempotent as well. We can use `TracePoint` to _enforce_ that (e.g. by raising an error whenever that contract is violated in development).

```ruby
module Idempotizer
  Traces = {}

  def self.included klass
    ret = nil
    Traces[klass] = TracePoint.new :return do |t|
      next unless t.self.is_a? klass

      method = t.self.method t.method_id
      # Methods which take input parameters generally produce different return
      #   values with different inputs. Regrettably, TracePoint doesn't seem
      #   to give us a reasonable way to get the inputs to this function call.
      next unless method.arity == 0

      # Somewhat fiddly, but if we `raise`, we'll end up triggering another `return`
      # event but with `return_value == nil` and we want the earlier return value
      ret   = t.return_value if t.return_value
      
      # Call the method again (without traces) and compare the values
      check = t.disable { method.call }
      if check != ret
        raise "#{t.self}##{t.method_id} is not idempotent! #{check} != #{ret}"
      end
    end
    Traces[klass].enable
  end
end

class Demo
  include Idempotizer

  # This will now raise an error the second time it's called
  def now
    Time.now.to_f
  end

  def sum
    2 + 2
  end
end
```

# Other Ideas?

Hopefully you get the gist of what `TracePoint` can do, and how to use it. These examples are just a jumping off point though - if you've got another nice hack, [let me know](mailto:jamesdabbs@gmail.com?subject=TracePoint).
