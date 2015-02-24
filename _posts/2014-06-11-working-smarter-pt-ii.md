---
layout: post
title: 'Working Smarter, pt. II'
date: 2014-06-11 20:13:09
tags:
- 'test'
- 'thing'
- 'Thing with spaces in it'
---
_Video of this talk available [on Youtube](https://www.youtube.com/watch?v=GzpOw8u6OV8), with thanks to [Frank Rietta](http://rietta.com/)_

_See [pt. I](http://jdabbs.ghost.io/working-smarter/) for background discussion_

Okay. Worker platform: selected. Let's do this.

### Listen to the Tests

_See commit [cbc86ea](https://github.com/jamesdabbs/air/commit/cbc86ea51badbcb99e7f11cd37cd7292f8260861)_

[Aliveness of TDD notwithstanding](https://plus.google.com/events/ci2g23mk0lh9too9bgbp3rbut0k), our current tests are exposing some problems with that `open` call …

* It's actually opening the cat gifs (which in fairness is pretty cute, but can clutter up your tabs quickly)
* It is _not_ testing that the `open` command is run, because is can't as currently structured

Being hard to test _can_ be a symptom of bad abstraction, and I think it is in this case. I'd prefer to wrap our shell interactions in an object that we can inspect and modify as needed (e.g. if we decide to support a platform without `open`). Here's an approach at that, taking a bit of a nod from `ActionMailer::Base#deliveries` -

```ruby
class Shell
  attr_reader :history

  def initialize limit: 100
    @history, @limit = [], limit
  end
  
  # Runs the command, maintaining a rolling window
  #   of recently executed commands
  def run cmd
    record cmd
    system cmd unless Rails.env.test?
  end

  def record cmd
    @history.shift if @history.length == @limit
    @history << cmd
  end
end
```

After [adding an initializer](https://github.com/jamesdabbs/air/blob/cbc86ea51badbcb99e7f11cd37cd7292f8260861/config/initializers/shell.rb) so that we can access it, we can use the shell as follows:

```ruby
class CatRequest < ActiveRecord::Base
  …
  
  def fulfill
    Air.shell.run "sleep 5" # Pretend this is harder than it really is
    update_attributes cat: Cat.choose
    Air.shell.run "open #{cat.download_path} -a 'Google Chrome'"
  end
end
```

and update the tests to make sure we're executing the right system call:

```ruby
expect( Air.shell.history.last ).to match /open.*#{req.cat.download_path}/
```

Bonus: since we don't actually run the commands, our tests no longer have to do the five second wait thing either. Win!

### Plumbing

_See commits [7f18f3d](https://github.com/jamesdabbs/air/commit/7f18f3df8e5d320486afb9eb388fac0d2bbf0d60) and [0b6bb4a](https://github.com/jamesdabbs/air/commit/0b6bb4abb55b6ea600dfc46e8cc3aa3a1c3f3e19)_

We ended up going with [Sidekiq](http://sidekiq.org/), but your needs may differ; take a look at [pt. I](http://jdabbs.ghost.io/working-smarter/) if you're wondering what's right for you. Setup was anticlimactically easy:

* Add `sidekiq` and `sinatra` (for `Sidekiq::Web`) to the Gemfile
* Install redis (`brew install redis` in my case)
* Mount `Sidekiq::Web` under the `/sidekiq` route [like so](https://github.com/jamesdabbs/air/commit/0b6bb4abb55b6ea600dfc46e8cc3aa3a1c3f3e19#diff-21497849d8f00507c9c8dcaf6288b136R6)

And then we just need to add a worker to do our fulfillment:

```ruby
class CatRequestWorker
  include Sidekiq::Worker

  def perform id
    cat_request = CatRequest.find id
    cat_request.fulfill
  end
end
```

and call it instead of doing the fulfillment inline:

```ruby
def cat_me!
  req = cat_requests.create!
  # - req.fulfill
  CatRequestWorker.perform_async req.id
end
```

Note that we're passing off the id of the Request that we want to fulfill, not the Request itself. You should __always__ pass JSON-able arguments into your jobs, and look up current state when the job actually starts to run. Trying to pass e.g. an ActiveRecord in could cause problems when trying to (de)serialize through Redis, and the record could be out of date by the time the worker actually runs.

Good news! We're done. Fire up Sidekiq (with `bundle exec sidekiq`) and try it out - you should be able to hammer the button repeatedly and (after a short wait), get a whole [pounce](http://en.wikipedia.org/wiki/List_of_collective_nouns_in_English#cite_ref-sdzoo_1-18) of cat gifs.

### Red ⇒ Green

_See commit: [7d34a0e](https://github.com/jamesdabbs/air/commit/7d34a0e3fa197d85a315e9e53776813c27e62644)_

Bad news! We broke the spec~~s~~. Running manually seems to work though … what's going on? Let's take a closer look at [the relevant test](https://github.com/jamesdabbs/air/blob/122376454891096f862d39a60936ee550d840853/spec/features/cat_me_spec.rb#L17):

```ruby
click_on "Cat Me"
req = @user.cat_requests.last
expect( req.cat ).to be_present
```

Hoist by our own petard! We introduced background workers so that our code wouldn't have to wait around while we wrangled up some pictures, but now our tests aren't waiting for the things they should be testing! We _could_ do something to introduce a delay here (even [pry](http://pryrepl.org/)ing for long enough), but it turns out this is a common problem that most worker gems have tools for. In Sidekiq's case it's:

```ruby
require 'sidekiq/testing'
Sidekiq::Testing.inline!
```

[As you can see](https://github.com/mperham/sidekiq/blob/015876bbd800b7a31e537eeb37f5581a29aeb96e/lib/sidekiq/testing.rb#L68), when running `inline!`d, Sidekiq simply fakes the Redis round-trip by dumping and loading though JSON and then calling perform directly, without sparking off a new thread.

### Coping with Failure

_See commit: [1223764](https://github.com/jamesdabbs/air/commit/122376454891096f862d39a60936ee550d840853)_

Especially when dealing with external services, we have to allow for the possibility of a worker failing. Different systems do this somewhat differently, but Sidekiq will [automatically retry failed jobs](https://github.com/mperham/sidekiq/wiki/Error-Handling#automatic-job-retry), as you can watch in the admin area by unleashing the [chaos monkey](http://techblog.netflix.com/2012/07/chaos-monkey-released-into-wild.html) on your worker:

```ruby
raise "NOPE" if rand < 0.9
```

This is convenient, but has some ramifications on designing your workers: if a job dies somewhere in the middle, it'll retry from the start, so we need to make our workers as robust as possible. In our case, I see two main defensive changes to make -

Since jobs may be run multiple times, we should make sure we never fulfill a request more than once:

```ruby
def fulfill!
  return if cat_id.present?
  …
end
```

If we add logic for canceling a request by deleting it before it gets fulfilled, the worker's lookup will fail and keep retrying. We should change it to something like:

```ruby
def perform id
  cat_request = CatRequest.where(id: id).first
  cat_request.fulfill! if cat_request
end
```

There. Bulletproof. Now ...

![moar cats](http://edgecats.net/)
