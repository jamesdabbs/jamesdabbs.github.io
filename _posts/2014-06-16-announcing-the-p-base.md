---
layout: post
title: 'Announcing: The π-Base'
date: 2014-06-16 16:56:49
tags:
- 'test'
- 'thing'
- 'Thing with spaces in it'
---
_It's alive! [Go look](http://topology.jdabbs.com)!_

The π-Base is a database of topological information, similar to Steen & Seebach's classic [Counterexamples in Topology](http://books.google.com/books/about/Counterexamples_in_Topology.html?id=DkEuGkOtSrUC), but with automated deduction and powerful search. It is the tool that I wished existed when I started looking into [cozero complemented](http://topology.jdabbs.com/properties/61) spaces, replacing a stultifying literature search with the following process:

* Add the [cozero complemented property](http://topology.jdabbs.com/properties/61)
* Record its relationships with other known properties: [perfectly normal](http://topology.jdabbs.com/theorems/127), [completely regular](http://topology.jdabbs.com/theorems/126) and [ccc](http://topology.jdabbs.com/theorems/145)
* Let the site deduce what it can about the [examples it knows about](http://topology.jdabbs.com/spaces)
* Query for [spaces which are not determined by the known theorems](http://topology.jdabbs.com/search?q=%3F%7B%2261%22%3Atrue%7D)

The ultimate goal being to pool knowledge about interesting examples, and to let people get straight to examining interesting cases in hopes of extrapolating out new theorems (... which go back in to the database, creating a nice little feedback loop).

I also hope that the site can be a useful pedagogical tool, since it lets students explore [results that may seem counterintuitive](http://topology.jdabbs.com/search?q=%7B%22and%22%3A%5B%7B%2228%22%3Atrue%7D%2C%7B%2226%22%3Atrue%7D%2C%7B%2227%22%3Afalse%7D%5D%7D), and since all deductions are traceable back to first principles. [Austin Mohr](http://austinmohr.com/home/) - an Assistant Professor at Nebraska Wesleyan University - has been working in this direction, and I am indebted for his contributions.

## Planned Features

There are several planned improvements for the site, most of which are in the [Github issue tracker](https://github.com/jamesdabbs/pi-base.hs/issues?state=open). If anything would be particularly useful to you, please create a feature request there (or :+1: an existing one).

As it stands, deduction is fairly simple-minded, essentially just applying modus ponens / tollens. My hope is to one day integrate with existing proof assistants like [Coq](http://coq.inria.fr/), so that we can formally describe the internal structure of these spaces and verify _all_ assertions. This should also allow us to track more subtle interactions like spaces embedding in others, or properties being weakly hereditary. This is a large task, but if you are interested in helping, please [get in touch with me](mailto:jamesdabbs+pibase@gmail.com).

## Getting Involved

Ultimately the best thing you can do is just use the site. If you find bugs, [file a bug report](https://github.com/jamesdabbs/pi-base.hs/issues?state=open) (though I should automatically get an email if the server errors). If you'd like a features that doesn't exist yet, [file a feature request](https://github.com/jamesdabbs/pi-base.hs/issues?state=open). If you have any comments or questions [drop me a line](mailto:jamesdabbs+pibase@gmail.com). Any user is able to add new spaces, properties and theorems, so feel free to contribute whatever your interest is. There are some admin-only tools, like deleting false assertions and reverting edits - please contact me if you need any of those.

I have added several assertions without proof, for the sake of getting interesting search results. You can see those on each space under the "needing proof tab". It would be a big help if you can fill these in. Along those lines, there is a "contribute" button in the nav bar that will take you to a random assertion in need of a proof.

If you are interested in contributing to the software side of things, there is [a Github repo](https://github.com/jamesdabbs/pi-base.hs). Pull requests welcome. If you are interested, but don't have the Haskell chops or don't know where to start, [get in touch](mailto:jamesdabbs+pibase@gmail.com) and I'll be glad to work with you.

Happy Topologizing!
