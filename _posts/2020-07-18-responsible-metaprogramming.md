---
layout: post
title: Responsible Metaprogramming
date: 2020-07-21 12:00:00
tags:
- Technical
- Ruby
- Metaprogramming
permalink: /responsible-metaprogramming/
---

When done well, metaprogramming enables a very high-level, expressive style of coding. Some of the real gems of the Ruby ecosystem - like `activerecord` and `rspec` - lean heavily (and mostly successfully) on metaprogramming. It's a powerful technique, but easily misused. Here's what I've learned about metaprogramming so far - both the how-tos and and when-not-tos. <!--more-->

**Caveat:** this post is informed by my role at [Procore](https://www.procore.com/engineering) writing [Boring](https://twitter.com/searls/status/372085430373453824) Business-class Software on a large team. If you're hacking on a personal project, feel free to selectively disregard the [**Principles**](#principles), skip on down to the [**Tools**](#tools), and metaprogram your heart out. There are some absolutely perfect and delightful DSLs like [Sonic Pi](https://sonic-pi.net/) out there that break most of these "rules".

# Principles

## Declarative Shell, Object-Oriented Core

On balance, Metaprogramming tends to make it easier for developers to express their intent, but harder to follow what's _really_ happening at runtime. As such, metaprogramming is well suited for declarations about object configuration, that happen at "compile" time (or whatever your application's "startup" phase is), and not "runtime". `ActiveRecord::Base.has_many` is a prime example here: it's _incredibly_ complex to trace what that actually does at runtime, but that rarely matters; we just declare our data model, and trust that the DSL will work it out.

Most of the complexity in day-to-day development in a large, existing system is about coordinating interactions of objects at runtime (and especially recombining them in new ways that they weren't necessarily designed for). Metaprogramming aside, this is why it's often helpful to keep your objects simple and lift the complexity into the factories that assemble them.

Altogether, I generally find that DSLs work very well in factory methods - where a high-level, grokkable declaration of the configuration is valuable - and tend not to work as well for describing lower-level, runtime object interactions. [Most commonly](#declarative-factories), my DSLs are very thin factory layers that are only responsible for `new`ing up an object and it's collaborators. You _could_ always just use the objects directly, but the DSL gives developers an easy-to-write and easy-to-read way to declare that object configuration (and gives me a place to validate that declaration).

Metaprogramming is like an onion - if find yourself spending hours on end hacking away at it, you and everyone around you are going to cry. Also, there are layers.

## Keep It Composed

_Most_ of the time, when metaprogramming goes bad, it's because someone built a domain-specific language without really reflecting on the fact that they were _writing a ([little](http://staff.um.edu.mt/afra1/seminar/little-languages.pdf)) language_. Most object-oriented programmers have spent a considerable amount of time mastering the tools of their trade - e.g. inheritance and composition - and depriving them of those tools is a _high_ cost that has to be minimized or justified.

Good OO design is successful precisely because it allows you to easily re-use your objects in new, novel contexts. Spend some time considering: what happens when a developer wants to extend your DSL? Re-use parts of it in new ways? Are there escape hatches to get back down to Plain Ol' Ruby? Or is your language executed in a separate environment, with narrowly defined interface points to the host language? Either is fine, but it should be clear to your users what the boundaries between your DSL and the rest of the Ruby system are.

## Setting Expectations

Many of the guidelines above are shorthand for encouraging the [principle of least astonishment](https://en.wikipedia.org/wiki/Principle_of_least_astonishment). If you're building a language for other developers, you want it to be intuitive and ergonomic for them. `rspec` is a rather astonishing library, but it's "unsurprising" in the sense that you express yourself in code more-or-less as you would express yourself to a co-worker.

If you can find natural reference points to help make your DSL "unsurprising", great. But don't overlook the other ways that you can set clear expectations with your users - like good documentation, examples, and consistent interfaces.

# Tools

Ruby has a dizzying array of tools available for metaprogramming. What follows is an  overview of the ones that I tend to find most helpful - when I reach for them, and what the sharp edges are.

Programming generally involves inspecting, creating and calling classes and methods. Unsurprisingly, there are metaprogramming tools to do all the same things.

## Defining Classes

Ruby is strongly object-oriented. That means that _everything_ in Ruby is an `Object`, including `Class`es and `Module`s. You can define new `Class`es on the fly, return them from methods, and don't have to assign them to named constants.

```ruby
class Base
  # ...
end

def base_with_field(name)
  # define a specialized subclass of `Base` with a named field
  Class.new(Base) do
    attr_accessor name
  end
end
```

Similarly, many things that you might not _think_ of as methods on classes, are still. For instance

```ruby
class Collection
  include Enumerable
  # ...
end
```

is equivalent to

```ruby
class Collection
  self.include(Enumerable)
  # ...
end
```

or

```ruby
Collection.include(Enumerable)
```

## Defining Methods

You're probably already familiar with a few methods-that-define-methods, like `attr_reader` or `alias_method`. There are a few other really handy options for defining methods on the fly.

### `define_method` &c

The most straightforward way to dynamically define a method is the aptly-named [`define_method`](https://apidock.com/ruby/Module/define_method), which defines methods on a class, just like a normal `def`.

```ruby
class Base
  def self.logging_attr_accessor(logger, *names)
    names.each do |name|
      define_method(name) do
        value = instance_variable_get(:"@#{name}")
        logger.info("Read #{name}=#{value}")
        value
      end

      # Defined methods can take arguments - even *splats,
      # keywords:, or &blocks - just like normal methods.
      define_method(:"#{name}=") do |value|
        instance_variable_set(:"@#{name}", value)
        logger.info("Set #{name}=#{value}")
        value
      end
    end
  end

  logging_attr_accessor Logger.new(STDOUT), :foo, :bar
end
```

There's also the less commonly used [`define_singleton_method`](https://apidock.com/ruby/Object/define_singleton_method) which can be used to define class methods (or methods on any single object).

### `method_missing`

[`method_missing`](https://apidock.com/ruby/BasicObject/method_missing) allows you to hook into Ruby's default `NoMethodError` handling, and supply your own fallback logic.

```ruby
class Object
  def method_missing(name, *args)
    match = name.to_s.match(/^try_to_(.*)/)
    if match
      begin
        send(match[1], *args)
      rescue
      end
    else
      super
    end
  end
end

"test".try_to_upcase # => "TEST"
"test".try_to_floop  # => nil
```

"Methods" defined with `method_missing` will always have some limitations - e.g. they don't show up in `pry`, and they may conflict with other named methods. A few rules here:

* Use `method_missing` sparingly
* Always define a [corresponding `respond_to_missing?`](https://thoughtbot.com/blog/always-define-respond-to-missing-when-overriding)
* If possible, also define an explicit callable method, even if it's more verbose.

As an example, `rspec` uses `method_missing` to make these two equivalent

    ```ruby
    expect(result).to be_correct
    expect(result.correct?).to eq true
    ```

which is definitely _cool_, but not really _necessary_. I tend to find it clearer and easier to maintain to have an single explicit method dedicated to handling those dynamic message

    ```ruby
    expect(result).to be(:correct)
    ```

I'm serious about "sparingly". I have exactly _one_ `method_missing` implementation in production right now. It's similar to the `MagicMap` example below, and I still periodically wonder if it was a good idea.

## Calling Methods

### `send` & `public_send`

If you don't know what method you're calling until runtime, it's common to use [`send`](https://apidock.com/ruby/Object/send)

```ruby
def format(user, order=[:first_name, :last_name])
  order.map { |field| user.send(field) }.join(', ')
end
```

The terminology "send" comes from thinking of _calling a method `M` on an object `O`_ (and it returning a value) as equivalent to _sending `O` the message `M`_ (and checking its response).

`send` will allow you to call methods that should be private - that's great if you're in a REPL, but almost always a Bad Idea otherwise. If you're sending a message that the receiver expects, you should be using [`public_send`](https://apidock.com/ruby/Object/public_send) instead.

### `instance_variable_get` & `instance_variable_set`

I almost always prefer to access the state of an object through its public interface, but there are occasions where you may need to get or set the internal state of an object directly. Ruby's got you covered there.

```ruby
object.instance_variable_get(:@variable_name)
object.instance_variable_set(:@variable_name, value)
```

This can be especially handy in constructors

```ruby
class ValueObject
  attr_reader(*EXPECTED_FIELDS)

  def initialize(json_hash)
    json_hash.each do |key, value|
      instance_variable_set(key.to_sym, value)
    end
  end
end
```

### `instance_eval` & `instance_exec`

Less common, but you may want to dynamically change the _receiver_ of a block (the implicit `self` and the `@ivar` context). You can do that using [`instance_exec`](https://apidock.com/ruby/BasicObject/instance_exec) or [`instance_eval`]((https://apidock.com/ruby/BasicObject/instance_eval)

```ruby
class MagicMap
  attr_reader :declarations

  def initialize
    @declarations = {}
  end

  def method_missing(name, *args)
    @declarations[name] = args
  end

  def self.declare(&dsl)
    new.tap do |m|
      m.instance_exec(&dsl)
    end.declarations
  end
end

MagicMap.declare do
  foo :bar
  baz :quux
end
# => { foo: :bar, baz: :quux }
```

Do note that this gives you another options for accessing instance variables, if you know the name of them

```ruby
object.instance_exec do
  @foo = :bar
  @baz
end
```

This can similarly can be used to define methods, but I tend to prefer using the more purpose-tailored and intention-revealing methods.

The only differences between `instance_exec` and `instance_eval` are that `instance_exec` allows you to pass arguments to your block (which is good) and `instance_eval` allows you to pass in a string to be evaluated as Ruby code (which is bad). As such, I generally use `instance_exec` alone, and avoid `instance_eval`.

`instance_exec` is powerful, but should be used sparingly. It can be _very_ surprising when `self` isn't what a user expects it to be.

### `eval`

Don't. Just don't. Seriously - with a modern Ruby, I've never seen a use case where a literal `eval` was _necessary_. It just opens up a host of security concerns.

## Inspecting Methods

[`Object#respond_to?`](https://apidock.com/ruby/Object/respond_to%3F) and [`Module#method_defined?`](https://apidock.com/ruby/Module/method_defined%3F) let you tell if a method already exists on an object or module, respectively. [`Object#methods`](https://apidock.com/ruby/Object/methods) lets you get the full list of all messages that an object responds to.

If you want more information about an existing method, you can use tools like [`Module#instance_method`](https://apidock.com/ruby/Module/instance_method) or [`Object#method`](https://apidock.com/ruby/Object/method) to get an object representing the method and ask it questions about things like its `source`, `source_location`, `parameters` or `arity`.

## Inspecting Classes

[`Object.is_a?`](https://apidock.com/ruby/Object/is_a%3F) and [`Class.ancestors`](https://apidock.com/ruby/RDoc/ClassModule/ancestors) let you check where in the inheritance hierarchy any given object sits.

`ObjectSpace` is an interesting sledgehammer for inspecting _all_ of the classes in your system. This is heavy enough that I tend not to use it in production, but I wrote [an earlier post](/exploring-objectspace) with some examples of what's possible here.

## Hooks and Extension Points

One useful programmatic option that's _not_ available when programming by hand is extending some of Ruby's built in inheritance mechanisms, e.g. using [`Class.inherited`](https://apidock.com/ruby/Class/inherited) or [`Module.included`](https://apidock.com/ruby/Module/included) to run extra code when these events happen.

### TracePoint

Taking extension points a step further, Ruby allows you to hook into the VM layer and react to events like methods being defined or called. This is another big, heavy tool that I've [written about separately](/tracepoint-by-example) (and tend to avoid in production code).

# Recipes

## Declarative Factories

I have a fairly standard snippet that I use for factory methods

```ruby
module Definable
  def self.included(other) # 1
    other.extend(ClassMethods)
  end

  module ClassMethods
    def define(*args, &setup) # 2
      dsl = self::DSL.new(*args) # 3
      setup.arity.zero? ? dsl.instance_exec(&setup) : setup.call(dsl) # 4
      dsl.build # 5
    end
  end
end
```

Unpacking the parts here:

1. We use the [`included` hook](https://apidock.com/ruby/Module/included) to allow this module to define class methods when `included`. (If you have access to `ActiveSupport::Concern`, you should probably just use that instead.)
2. `Definable` classes have a `define` method that takes a block (the DSL to run), and possibly some other arguments.
3. `Definable` classes must define an inner `DSL` class that provides the execution context for that DSL block.
4. _Usually_ it's easiest if the DSL block is executed with its implicit `self` being the `DSL` instance. This line does that by default, but provides users with an escape hatch:

    ```ruby
    Thing.define do
      # `self` is a `Thing::DSL` instance
    end

    Thing.define do |dsl|
      # `dsl` is the `Thing::DSL` instance
      # `self` is still `Thing`
    end
    ```

5. The inner `DSL` class must define a `build` method, which is responsible for calling `new` on the defined class.

I find that this setup encourages several nice effects:

* The setup complexity is isolated to the `DSL` class, which has that as its sole responsibility
* The `DSL` is just an equivalent way of building objects - users can eject out and use those objects directly whenever needed
* Users can also eject out from any magic `self`-shifting if they need to
* The repeated structure leads to less surprise (admittedly, once you're familiar with the pattern)

## Wrapping Module

A pattern I've seen pop up a few times now involves needing to dynamically wrap some-or-all methods on an existing object with a block - e.g. to add timing, [science experiments](https://github.com/github/scientist#scientist), or error handling. By putting together a few of the techniques above, we can package up this pattern:

```ruby
class MethodWrapper
  def initialize(&handler)
    @handler = handler # 1
  end

  def wrap(target_class, methods=target_class.instance_methods(false)) # 2
    handler = @handler # 3

    wrapper = Module.new do # 4
      methods.each do |name|
        define_method(name) do |*args|
          handler.call(name) do # 6
            super(*args) # 5
          end
        end
      end
    end

    target_class.prepend(wrapper) # 5
  end
end
```

1. We instantiate the wrapper with a block that we'll use to decorate methods.
2. We supply a `target_class` that we want to decorate and a set of method names (by default, all methods defined on the class).
3. What follows will execute in a different object context, so we won't have a reference to our `@handler` instance variable. We assign it to a local variable, so that subsequent blocks close over and include it.
4. `Module`s are objects too, so we can instantiate a new one which dynamically defines all the given `methods`.
5. We're going to `prepend` the module, so calls to `super` will then call the existing implementation in `target_class`.
6. Altogether, the module method implementations wrap each named method in the provided `handler`, which receives the wrapped method name as a parameter.

With that in place, we can add decorated behavior like so

```ruby
wrapper = MethodWrapper.new do |name, &method|
  start  = Time.now
  result = method.call
  puts "#{name} took #{Time.now - start}s"
  result
end

wrapper.wrap(String).new("hello").upcase
# upcase took 2.0e-06s
# => "HELLO"
```

# `send` Off

Ruby's superpower is that is lets developers express themselves in any way they can dream up. When working with other developers, remember that you're writing for your teammates as much as for yourself and the interpreter. Used well, metaprogramming allows you to develop a shared language that's well-tailored to the problem at hand, and a joy to work with. Take your cues from Ruby, and try to build little languages that [make people happy](https://learn.co/lessons/matz-readme).
