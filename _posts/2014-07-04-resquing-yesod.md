---
layout: post
title: 'Resquing Yesod'
date: 2014-07-04 01:42:37
tags:
- 'Technical'
- 'Haskell'
---
### Building a background worker system in Haskell

I've long been intrigued by [Haskell](http://learnyouahaskell.com/chapters) and recently have been reworking some existing apps in [Yesod](http://learnyouahaskell.com/chapters) to get more hands-on experience (most notably, working on the [Pi-Base](https://github.com/jamesdabbs/pi-base.hs)). There's a lot to like - the type system offers some pretty strong correctness guarantees, but more significantly, it makes refactoring and developing feel a whole lot less like work and a whole lot more like playing with Legos. But coming from Rails and the ridiculously helpful Ruby ecosystem, I've struggled to find replacements for a few of my workhorse gems.

For the home server I've started working on, I found myself needing to do some periodic background tasks, which probably means forking off a clock-worker. While there are _lots_ of different ways to approach this, this is essentially a solved problem in the Rails world; you should pretty much be able to drop in [any one of several gems](http://jdabbs.com/working-smarter/) and call it a day. I'll admit I'm new to the Haskell ecosystem, but it doesn't seem as cut and dried here. In fairness, this could be in part because the pieces are all already there and assembling them yourself isn't all that bad.


### The Pieces

As I see it, there are 3 main things to figure out how to do:

* hook in to the Yesod boot process and fork off workers
* coordinate work between the web app and workers
* run Handler-monad style functions outside of a handler

And each of those is fairly tractable. I've played around with forking off handlers before using [`handlerToIO`](https://hackage.haskell.org/package/yesod-core-1.2.16/docs/Yesod-Core-Handler.html#v:handlerToIO) or [`forkHandler`](https://hackage.haskell.org/package/yesod-core-1.2.16/docs/Yesod-Core-Handler.html#v:forkHandler) (in Yesod 1.2.8+). The scaffolded site already [forks a thread to process the logs](https://github.com/jamesdabbs/sarah/blob/a3d643579b2a119a880e8c53e7f45204e462e5d9/Application.hs#L82) on boot, so we should be able to imitate that. And there are many different options for coordinating jobs - including [Redis](http://sidekiq.org/) or [even the Database itself](https://github.com/collectiveidea/delayed_job). But I never found a Heroku-friendly drop-this-in-and-everything-just-works Haskell equivalent to [sucker_punch](https://github.com/brandonhilkert/sucker_punch), so I decided to poke around and see if I couldn't make my own. Here's what I found:


#### Spawning Workers

[Control.Concurrent](https://hackage.haskell.org/package/base-4.7.0.0/docs/Control-Concurrent.html) has most of the magic we need for running concurrent workers - most notably [`forkIO`](https://hackage.haskell.org/package/base-4.7.0.0/docs/Control-Concurrent.html#v:forkIO) (which is a lightweight thread; compare to [`forkOS`](https://hackage.haskell.org/package/base-4.7.0.0/docs/Control-Concurrent.html#v:forkOS)). The process is complicated somewhat by the other concerns, but spinning up `n` workers should look something like

```haskell
spawnWorkers n = do
  replicateM_ n . forkIO . forever $ do
    mj <- dequeueJob
    case mj of
      Just job -> perform job
      Nothing -> threadDelay 1000000
```

for an appropriate definition of `dequeueJob :: IO (Maybe Job)` and `perform :: Job -> IO ()`. This will consume jobs as long as they are available and then fall back to polling every second for new jobs.


#### Coordinating Jobs

That begs a question ... how should we be tracking what jobs are queued? [Redis](https://hackage.haskell.org/package/hedis) is a great fit here, but Haskell provides us with some tools for making a fairly robust-yet-convenient system without any extra dependencies. I'm using [STM's TVars](http://hackage.haskell.org/package/stm-2.2.0.1/docs/Control-Concurrent-STM-TVar.html) for thread-safe atomic access to the shared queue (using a [`Data.Sequence.Seq`](http://hackage.haskell.org/package/containers-0.5.5.1/docs/Data-Sequence.html) instead of a `List`, since we'll mostly be reading from one end and writing to the other).

```haskell
import Control.Concurrent
import qualified Data.Sequence as S

type Job = ??? -- A sum type for each of the app's different jobs
type JobQueue = TVar (S.Seq Job)

-- Definitions left as an exercise for the reader
enqueue :: S.Seq a -> a -> S.Seq a
dequeue :: S.Seq a -> Maybe (a, S.Seq a)

-- The public API for queueing a job
enqueueJob :: JobQueue -> Job -> IO ()
enqueueJob qvar j = atomically . modifyTVar qvar $ \v -> enqueue v j

dequeueJob :: JobQueue -> IO (Maybe Job)
dequeueJob qvar = atomically $ do
  q <- readTVar qvar
  case dequeue q of
    Just (x,xs) -> do
      writeTVar qvar xs
      return $ Just x
    Nothing -> return Nothing
```

that gets us our `dequeueJob` function, except that we'll need to keep a reference to the queue around:

```haskell
spanWorkers n = do
  q <- atomically $ newTVar S.empty
  replicateM_ n . forkIO . forever $ do
    mj <- dequeueJob q
    case mj of
      Just job -> perform job
      Nothing -> threadDelay 1000000
  return q
```

We'll need to spin up these workers when we boot the Yesod app, and will need to be able to access the returned queue e.g. from inside handlers, so this seems like a good thing to extend our foundation data type with.

```haskell
-- Foundation.hs
data App = App
  { settings :: AppConfig DefaultEnv Extra
  -- ...
  , jobQueue :: JobQueue
  }
```

Then we can start and store the queue

```haskell
-- Application.hs
makeFoundation conf = do
  -- ...
  q <- spanWorkers 3 -- Or set from the environment or settings
  let logger = Yesod.Core.Types.Logger loggerSet' getter
      foundation = App conf s p manager dbconf logger q
  -- ...
```

Now we can easily enqueue a new job from inside any `Handler`

```haskell
queue :: Job -> Handler ()
queue job = do
  app <- getYesod
  liftIO $ enqueueJob (jobQueue app) job
```


#### Running Queries

So we can run jobs, but right now they run in the `IO` monad, so they are rather limited compared to `Handlers`. I'd like to be able to do something like a [`handlerToIO`](http://hackage.haskell.org/package/yesod-core-1.1.1/docs/Yesod-Handler.html#v:handlerToIO) here but don't have a handler to fork from (and it wouldn't quite make sense even if we did). A simple, if inelegant, fix is to pass through the db configuration and run them manually. Doing that, we finally have

```haskell
spawnWorkers :: PersistConfigPool PersistConf -> PersistConf -> Int -> IO JobQueue
spawnWorkers pool dbconf n = do
  q <- atomically $ newTVar S.empty
  replicateM_ n . forkIO . forever $ do
    mj <- dequeueJob q
    case mj of
      Just job -> perform pool dbconf job
      Nothing -> threadDelay 1000000
  return q
```

and we can run queries inside a `perform` call using

```haskell
runDB' f = runStdoutLoggingT . runResourceT $ runPool dbconf f pool
```

Check out [Jobs.hs](https://github.com/jamesdabbs/sarah/blob/b3236e44d6d9cd1f47c3bfd4f9c07d498c769c19/Jobs.hs) and the [Foundation.hs integration](https://github.com/jamesdabbs/sarah/commit/a701e186011e1ae6b9ca4b0fc38e4f4bce5b5620#diff-4ff81c1023e92f161457e96254132f46L25) for full details.


### Putting Them Together

_See commit [b3236e4](b3236e44d6d9cd1f47c3bfd4f9c07d498c769c19) for the full project with this implemented_

As mentioned, the project motivating these is a home server that does things like sync'ing RSS feeds periodically. We can try out this job system by stubbing out a feed sync job

```haskell
Feed
  url Text
  createdAt UTCTime
  lastRunAt UTCTime
  nextRunAt UTCTime
```

```haskell
data Job = RunFeedJob FeedId

runDBIO pool dbconf f = runStdoutLoggingT . runResourceT $ runPool dbconf f pool

-- Dummy implementation:
--   look up the Feed from the database
--   if found, log the URL we would hit and then pause for a random length of time
perform pool dbconf (RunFeedJob _id) = do
  now <- liftIO getCurrentTime
  liftIO . putStrLn $ (show now) <> "  -- Trying " <> (show _id)
  mfeed <- runDBIO pool dbconf . get $ _id
  liftIO $ case mfeed of
    Just feed -> do
      putStrLn $ (show now) <> "  -- Running feed '" <> (show $ feedUrl feed) <> "'"
      -- Pretend these are variably complicated units of work
      sleep <- randomRIO (1,10)
      threadDelay $ sleep * 1000000
    Nothing -> return ()
```


Kicking off some jobs with

```haskell
createFeed :: Int -> Handler FeedId
createFeed n = do
  now <- liftIO getCurrentTime
  runDB . insert $ Feed url now now now
  where url = T.pack $ "this is feed url #" ++ show n

go :: Handler ()
go = do
  feeds <- mapM createFeed [1..10]
  mapM_ (runDB . delete) $ take 5 feeds
  mapM_ (queue . RunFeedJob) feeds
```

and 3 workers running we get

```
2014-07-03 15:45:57.72946 UTC  -- Trying Key {unKey = PersistInt64 1}
2014-07-03 15:45:57.729715 UTC  -- Trying Key {unKey = PersistInt64 2}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 1] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:57.730059 UTC  -- Trying Key {unKey = PersistInt64 3}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 2] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 3] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:57.732636 UTC  -- Trying Key {unKey = PersistInt64 4}
2014-07-03 15:45:57.732917 UTC  -- Trying Key {unKey = PersistInt64 5}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 4] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:57.733841 UTC  -- Trying Key {unKey = PersistInt64 6}
2014-07-03 15:45:57.734179 UTC  -- Trying Key {unKey = PersistInt64 7}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 6] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 5] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 7] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:57.733841 UTC  -- Running feed '"this is feed url #6"'
2014-07-03 15:45:57.735855 UTC  -- Trying Key {unKey = PersistInt64 8}
2014-07-03 15:45:57.734179 UTC  -- Running feed '"this is feed url #7"'
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 8] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:57.735855 UTC  -- Running feed '"this is feed url #8"'
2014-07-03 15:45:58.738309 UTC  -- Trying Key {unKey = PersistInt64 9}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 9] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:58.738309 UTC  -- Running feed '"this is feed url #9"'
2014-07-03 15:45:59.740272 UTC  -- Trying Key {unKey = PersistInt64 10}
[Debug#SQL] "SELECT \"url\",\"created_at\",\"last_run_at\",\"next_run_at\" FROM \"feed\" WHERE \"id\"=?" [PersistInt64 10] @(persistent-1.3.1.1:Database.Persist.Sql.Raw ./Database/Persist/Sql/Raw.hs:26:12)
2014-07-03 15:45:59.740272 UTC  -- Running feed '"this is feed url #10"'
```

which is consistent - we blow through the first 5 deleted feeds in no time, and then start the next 3 right away, then pick up the rest of the queue as the other ones finish.


### Future Improvements

I'd like to release this as a package (as much for the experience of making a package as anything), but there are a few improvements I want to make first. Note that while the `perform` function supports `persistent`, it doesn't actually run in the `Handler` monad. It shouldn't, as it doesn't handle routes or parameters or templates or any of several things that `Handler`s do; but we are missing several niceties like error handling and `runDB . getBy404` style query helpers. I'd like to define a `Worker` monad (or more likely a `WorkerT` monad transformer) with all those conveniences, and simplify the public API to:

* Some way of defining your job data type (`instance Worker App where ...`?)`
* `enqueue :: Job -> Handler ()`
* `perform :: Job -> Worker ()`

I have no idea how to make that happen, but that should be a good excuse to dig deeper into the guts of [Yesod's Handler monad](http://www.yesodweb.com/book/yesods-monads). Stay tuned for that.
