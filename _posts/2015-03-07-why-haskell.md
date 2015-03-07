---
layout: post
title: 'Why Haskell'
date: 2015-03-07 15:40:45
image: http://upload.wikimedia.org/wikipedia/commons/thumb/1/1c/Haskell-Logo.svg/2000px-Haskell-Logo.svg.png
permalink: /why-haskell/
---
I'm an unabashed fan of Haskell. When I mention that (as I am wont to do), people tend to dismiss it: "oh he's one of those academic types, he _would_ like Haskell." And I'll admit – I wrote [my master's](http://dml.cz/bitstream/handle/10338.dmlcz/141613/CommentatMathUnivCarolRetro_52-2011-3_9.pdf) on monads, and stumbled in to Haskell when someone told me that you could actually use monads to _do_ things (pun very much intended). Yes, that's how I got to Haskell – but I've stayed because I believe it's a great step in solving several of the software industry's hard problems.

# For Building

If I were launching a startup today, I'd absolutely be willing to bet it on Haskell<sup><a href="#fn1" id="ref1">1</a></sup>. Here's why:

### Leveraging the Type System

Far and away, the most exciting thing about Haskell is its advanced type system and runtime:

* So much information is encapsulated in the types and verified at compile time that it becomes impossible to make certain large classes of mistakes. [Costly mistakes](http://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare). In the web world, using a framework like [Yesod](http://www.yesodweb.com/page/about) more-or-less eliminates the possibility of any XSS, CSRF, or SQL injection attacks, along with template errors or broken links. The team gets to spend time writing, not debugging and patching.
* Because of the type system, refactors are easy and the codebase can adapt to changing business needs quickly. The system stays maintainable, the team stays agile, and technical debt accumulates slowly.
* Since most of your codebase is functionally pure, it's much easier to optimize and parallelize – by compiler or by hand. You can write high-level code that performs at near-C speeds, and write provably-correct parallelized code without pulling your hair out chasing down race conditions.

### Hiring and Onboarding

Admittedly, with Haskell's comparatively small userbase, it'll be hard to find the right hire with the right experience. If you're running a Haskell startup, you're going to have to invest in training your new hires in the language. But:

* They'll be able to contribute quickly and confidently, because the type system makes it so hard to actually ship a bug. A while back, I [extracted a background Worker system from Yesod](/resquing-yesod/) – I understood relatively little of the internals that I was hacking on, but 1) I was productive, 2) I learned a ton in the process, and 3) I loved every second of it.
* While there aren't a ton of people out there with deep real-world experience, there are some very sharp folks who have been dabbling with Haskell and would love an opportunity to dive in and use it. Building on Haskell can be a big hiring advantage here.
* In general, your best people are your best people because they've invested in learning and bettering themselves. You're going to attract and retain them by presenting them with a challenge that will let them learn and grow, and providing them with the support to rise to that challenge.

# For Learning

I'm very interested in the idea of Haskell as a first language. I'm 100% sold on it as a second. Learning Haskell was the best thing I ever did for my Ruby skills. But there are upsides even for first time students:

### Constraints, Creativity, and Experimentation

Writing Haskell is a tightly-constrained activity. I take that as a positive. Certainly, it stops you from making many kinds of mistakes. But as someone who's taught a lot of Ruby, the "you can do anything you want" wide-open solution space can be completely overwhelming to a beginner. It's nice to have a language with a strong opinion of what's right. In general, constraints breed creativity.

Moreover, the compiler having your back is a huge boon to learning. You are free to experiment, confident that if it compiles, it's probably correct. No hidden bugs popping up later or far away – if your code has a problem, you'll get an explicit (if initially opaque) message telling you where and why. Refactoring in Haskell is as fun to me now as playing with Legos was twenty years ago, with much the same feel. It takes surprisingly little mental energy – you can often switch your brain off and let the compiler do all the hard work.

### Foundational Concepts

I'll be the first to admit that Haskell has a reputation of being hard to learn. Some people wear this as a badge of honor – "oh, you want to print something? Ok, first let me tell you about the monad laws …". While I understand that reflex, I think it's harmful to the Haskell community. You can absolutely be productive in Haskell without really grokking monads. For many years, the language didn't even _have_ monads! But people realized they were repeating several common patterns, and eventually – as good engineers do – found the right tool to abstract the solution.

Category theory is a well-studied discipline that provides a very rich vocabulary for talking about functions and how they compose. [Vocabulary has an interesting relationship with thought](http://www.radiolab.org/story/91725-words/), and while it's not at all necessary to learn category theory _before_ Haskell, I do like that it exposes you to foundational concepts that will shape the way you think about all of the code you write. Once you recognize a monoid or a monad, once you've internalized ideas about functional purity, [it changes the code you write in other languages](http://awardwinningfjords.com/2015/03/03/my-weird-ruby.html). Writing modular programs well is very much about understanding composability – why remain willfully ignorant of the vast body of work done studying how functions compose?

# Why Not Haskell?

Haskell is exciting and promising, but it'd be unfair to pretend that it's perfect. The runtime is incredibly sophisticated, but that makes it hard to reason about at times. There are certainly situations where I'd reach for C or Rust instead for low-level, performance critical code. But I think the more significant problems for Haskell to address are around the ecosystem and tooling. Cabal hell is certainly a problem and tooling is [spotty, but improving](http://www.yesodweb.com/blog/2014/11/case-for-curation) (though [Hoogle](https://www.haskell.org/hoogle/?hoogle=%28a+-%3E+b%29+-%3E+%5ba%5d+-%3E+%5bb%5d) is amazing).

As I see it, the biggest problem is that you can't "just jump in" to Haskell. I'm coming from the Ruby world where a potential learner can have a blog running in 15 minutes. This makes it much easier to experiment with the platform, and invariably some of the folks that try it out end up liking it and using it. Again, [Yesod](http://www.yesodweb.com/) seems to be making some great strides in that direction.

Similarly, while Haskell is great for building a product that's going to be around for a long time, startups often need to prove an idea quickly before committing to that kind of investment of time and money. In the Rails world, you can pull in a functional [auth layer](https://github.com/plataformatec/devise), [background worker system](http://sidekiq.org), or [payment module](https://github.com/peterkeen/payola) with a dozen lines of code. Working in Haskell, it too often feels like you're forced to re-invent the wheel and spend time working on things that _aren't_ your core business concern.

# What Next?

Most of those problems are a matter of adoption, and would be resolved if more people built with or learned about Haskell. That's largely why I'm writing this. But as the problem is one of community engagement, I'm very interested to hear what _you_ think:

If you run a business, would you consider building on Haskell? If not, what's stopping you? How do you feel about bringing on new devs that need language training? Would you hire a junior dev that _only_ knows Haskell?

If you don't know Haskell, would you consider learning it? If you have considered learning it, what stopped you? Lack of support materials? Of time? Of interest? Of employers?

If you have learned Haskell, what do you wish you knew earlier? What do you feel is lacking or painful? What would you think of presenting it as a first language? Is it hard because it's so different from other languages? Is it that people insist on presenting the hard parts? Or is it honestly just intrinsically hard?

If you have answers or questions or are just interested in this discussion, please [tweet](https://twitter.com/jamesdabbs), retweet, or [email](mailto:jamesdabbs@gmail.com?subject=Why Haskell) me.

And [try Haskell](https://www.haskell.org/).

---

<sup id="fn1">1) Of course, no tool is right for every job. Evaluate it yourself, considering the specific and unique needs of your business.<a href="#ref1">↩</a></sup>
