# Pipes [![Build Status](https://secure.travis-ci.org/mikepack/pipes.png)](http://travis-ci.org/mikepack/pipes) [![Dependency Status](https://gemnasium.com/mikepack/pipes.png)](https://gemnasium.com/mikepack/pipes) [![Code Climate](https://codeclimate.com/badge.png)](https://codeclimate.com/github/mikepack/pipes)

[RDoc](http://rubydoc.info/github/mikepack/pipes)

![Pipes](http://i.imgur.com/MND26.png)

Pipes is a Redis-backed concurrency management system designed around Resque. It provides a DSL for defining "stages" of a process. Each (Resque) job in the stage can be run concurrently, but all must finish before subsequent stages are run.

Conceivably, Pipes is a lightweight, advanced Resque queue. It can be dropped right in place of Resque.

## Example

At Factory Labs, we work on a system for which we must deploy static HTML files. We must render any number of HTML pages, assets, .htaccess files, etc so the static HTML-based site can run on Apache.

Here's a simplified look at our stages:

**Stage 1**
- Publish HTML files.
- Publish assets.
- Publish .htaccess.

**Stage 2**
- rsync files to another server.
- Upload assets to a CDN.

**Stage 3**
- Activate rynced files.
- Email people about deploy.

We want to ensure that all of **Stage 1** is finished before **Stage 2** begins, and likewise for **Stage 3**. However, the individual components of each stage can execute asynchronously, we just want to make sure they converge when all is finished.

This can be visualized as follows:

![Architecture](http://i.imgur.com/0CEmm.png)

## Installation

Add this line to your application's Gemfile:

    gem 'pipes'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pipes

## Usage

Pipes assumes you're conforming to the Resque API in your jobs, so you might have the following:

```ruby
module Writers
  class HTMLWriter
    @queue = :content_writers

    def self.perform(url = 'http://localhost:3000/')
      # ... fetch URL and save HTML ...
    end
  end
end
```

You'll generally need to do two things when working with Pipes:

1. Define a set of stages.
2. Run the jobs.

Let's look at these two steps individually.

### Defining Stages

As part of the configuration process, you'll want to define your stages:

```ruby
Pipes.configure do |config|
  config.stages do
    # Stage 1
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter,
      Writers::HtaccessWriter
    ]

    # Stage 2
    publishers [
      Publishers::Rsyncer,
      Publishers::CDNUploader
    ]

    # Stage 3
    notifiers [
      Notifiers::FileActivator
      Notifiers::Emailer
    ]
  end
end
```

There's more advanced ways of defining stages, more on that later.

Stages are defined lexically. That is, the order in which you define your stages in the config determines the order they will be run.

The name of the stage is arbitrary. Above, we have `content_writers`, `publishers` and `notifiers`, though there's no significant meaning. The name of the stage can be later extracted and presented to the user or referenced as a symbol.

### Running The Jobs

Once your configuration is set up, you can fire off the jobs.

The Pipes API is designed to mimic Resque:

```ruby
Pipes.enqueue([Writers::HTMLWriter, Publishers::Rsyncer])
```

The above line essentially says "here's the jobs I'm looking to run", at which point Pipes takes over to determine how to partition them into their appropriate stages. Pipes will break these two jobs up as you would expect:

```ruby
# Stage 1 (content_writers)
Writers::HTMLWriter

# Stage 2 (publishers)
Publishers::Rsyncer
```

You can also pass arguments to the jobs, just like Resque. In fact, any call to `Resque.enqueue` can be safely replaced with `Pipes.enqueue`, but the reverse is not true:

```ruby
# If you currently have:
# Resque.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page')
# ...you can replace it with:
Pipes.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page')
```

In the above case, all jobs' `.perform` methods would receive the `http://localhost:3000/page` argument. You can, of course, pass multiple arguments:

```ruby
module Writers
  class HTMLWriter
    @queue = :content_writers

    def self.perform(host = 'localhost', port = 3000)
      # ... fetch URL and save HTML ...
    end
  end
end

Pipes.enqueue(Writers::HTMLWriter, 'google.com', 80)
```

## Defining Job Dependencies

Pipes makes it easy to define dependencies between jobs.

Say you want the `Publishers::Rsyncer` to always run after `Writers::HTMLWriter`. You'll first want to modify your config:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => Publishers::Rsyncer}
    ]

    publishers [
      Publishers::Rsyncer,
      Publishers::CDNUploader
    ]
  end
end
```

By converting the individual job into a Hash, you can specify that you want `Publishers::Rsyncer` to always run after `Writers::HTMLWriter`. You can also specify multiple dependencies:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => [Publishers::Rsyncer, Publishers::CDNUploader]}
    ]

    publishers [
      Publishers::Rsyncer,
      Publishers::CDNUploader
    ]
  end
end
```

Defining arrays of dependencies is great, but if you're just reiterating all jobs in a particular stage, you can specify the stage instead:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => :publishers}
    ]

    publishers [
      Publishers::Rsyncer,
      Publishers::CDNUploader
    ]
  end
end
```

If you need to specify multiple dependent stages, you can provide an array of symbols:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => [:publishers, :notifiers]}
    ]

    publishers [
      Publishers::Rsyncer,
      Publishers::CDNUploader
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

Pipes will also resolve deep dependencies:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => :publishers}
    ]

    publishers [
      {Publishers::Rsyncer => Notifiers::FileActivator},
      Publishers::CDNUploader
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

In the above example, `Notifiers::FileActivator` will also be a dependency of `Writers::HTMLWriter` because it's a dependency of one of `Writers::HTMLWriters` dependencies (:publishers).

Running jobs with dependencies is the same as before:

```ruby
Pipes.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page')
```

The above code will run `Writers::HTMLWriter` in **Stage 1**, `Publishers::Rsyncer` and `Publishers::CDNUploader` in **Stage 2**, and `Notifiers::FileActivator` in **Stage 3**, all receiving the `http://localhost:3000/page' argument.

## Defining Stage Dependencies

Just as jobs can have dependencies, stages can as well.

Imagine you have multiple jobs in a given stage, all of which have the same dependencies:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => :publishers},
      {Writers::AssetWriter => :publishers}
    ]

    publishers [
      Publishers::Rsyncer
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

This isn't so DRY. You would be better off adding a stage dependency:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter
    ] => :publishers

    publishers [
      Publishers::Rsyncer
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

This tells Pipes that you would like all jobs in the `:content_writers` stage to have a depencency on all `:publishers`.

You can intermix types for stage dependencies, just like with job dependencies:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter
    ] => [:publishers, Notifiers::FileActivator]

    publishers [
      Publishers::Rsyncer
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

This will ensure that all `:publishers` and the `Notifiers::FileActivator` get run when either of the `:content_writers` are run.

As you would expect, Pipes will resolve deep dependencies for you as well:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter
    ] => :publishers

    publishers [
      Publishers::Rsyncer
    ] => :notifiers

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

The above will add `Publishers::Rsyncer` and `Notifiers::FileActivator` as dependencies of both `Writers::HTMLWriter` and `Writers::AssetWriter`.

Intermixing job and stage dependencies works, too, resulting in the same dependency graph as the above example:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter
    ] => :publishers

    publishers [
      {Publishers::Rsyncer => :notifiers}
    ]

    notifiers [
      Notifiers::FileActivator
    ]
  end
end
```

## Acceptable Formats for Jobs

Pipes allows you to specify your jobs in a variety of ways:

```ruby
# A single job
Pipes.enqueue(Writers::HTMLWriter)

# A single job as a string. Might be helpful if accepting params from a form
Pipes.enqueue('Writers::HTMLWriter')

# An entire stage
Pipes.enqueue(:content_writers)

# You can pass an array of any of the above, intermixing types
Pipes.enqueue([:content_writers, 'Publishers::CDNUploader', Notifiers::FileActivator])
```

## Configuring Pipes

Pipes allows you to specify a variety of configuration options:

```ruby
Pipes.configure do |config|
  # config.redis can be a string...
  config.redis = 'localhost:6379'
  # ...or a Redis connection (default $redis):
  config.redis = REDIS

  # config.namespace will specify a Redis namespace to use (default nil):
  config.namespace = 'my_project'

  # config.resolve tells Pipes to resolve dependencies when calling Pipes.enqueue(...) (default true):
  config.resolve = false

  config.stages do
    # ...
  end
end
```

If you're using Pipes in a Rails app, stick your configuration in `config/initializers/pipes.rb`.

## Pipes Options

You can pass a hash of options when enqueueing workers through Pipes.

**resolve**

By default, Pipes will resolve and queue up all dependencies of the jobs you are requesting. You can turn off dependency resolution by passing in some additional Pipes options as the third argument:

```ruby
Pipes.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page', {resolve: false})
```

When **resolve** is false, only `Writers::HTMLWriter` will be run, ignoring dependencies.

**allow_duplicates**

If jobs are already queued up in Pipes and you'd like to enqueue more jobs, you may need to specify that only certain jobs be duplicated in the queue.

```ruby
Pipes.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page', {allow_duplicates: :content_writers})
# ..or an array of stages..
Pipes.enqueue(Writers::HTMLWriter, 'http://localhost:3000/page', {allow_duplicates: [:content_writers, :publishers]})
```

When Pipes enqueues `Writers::HTMLWriter` and all its dependencies, it will check whether any jobs with the same class name already exist in the queue. If a job has already been queued up with the same class name and **does not** belong to one of the stages provided to **allow_duplicates**, it is ignored.

This option helps prevent adding redundant jobs to the queue. See the section *Queueing Up Additional Jobs*.

## Working With Resque Priorities

Pipes is designed to work on top of Resque's already-existing queueing system. That is, the queue priorities Resque provides will continue to be honored.

Combining Resque's priority queues with Pipe's stages can produce fine-grain control over how your jobs get processed. By using the normal `@queue` instance variable, and specifying priorities when starting up your Resque workers, you can control the order in which jobs get processed for each individual stage.

Say we had the following jobs:

```ruby
module Writers
  class HTMLWriter
    @queue = :priority_1

    def self.perform; end
  end
end

module Writers
  class AssetWriter
    @queue = :priority_2

    def self.perform; end
  end
end
```

Both `Writer::HTMLWriter` and `Writer::AssetWriter` are configured for the same stage:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      Writers::HTMLWriter,
      Writers::AssetWriter
    ]
  end
end
```

Start up Resque with the usual priority list:

```bash
$ QUEUES=priority_1,priority_2 rake resque:work
```

Run the jobs through Pipes:

```ruby
Pipes.enqueue(:content_writers)
```

Pipes will queue up both `Writer::HTMLWriter` and `Writer::AssetWriter` in Resque. Resque takes over and respects the queue priorities, first running `Writers::HTMLWriter`, then `Writers::AssetWriter`.

## Queueing Up Additional Jobs

Say you have a job, `Writers::HTMLWriter`, whose purpose is to fire off additional jobs to accomplish the real work. This is actual the case for us at Factory Labs. Our `HTMLWriter` fires off additional jobs who do the heavy lifting of parsing page contents, and writing to a file.

Our `HTMLWriter` fires off additional writers:

```ruby
module Writers
  class HTMLWriter
    @queue = :content_writers

    def self.perform(locale)
      Pages.all.each do |page|
        # Enqueue additional jobs to do the real work
        Pipes.enqueue(Writers::PageWriter, page.id, locale, {allow_duplicates: [:content_writers]})
      end
    end
  end

  class PageWriter
    @queue = :content_writers

    def self.perform(page_id, locale)
      # We would normally do stuff with the locale...
      url     = page_url(Page.find(page_id))
      content = URI.parse(url).read

      File.new('index.html', 'w') do |f|
        f.write(content)
      end
    end
  end
end
```

Both jobs are configured for the same stage, with a dependency on `:publishers`:

```ruby
Pipes.configure do |config|
  config.stages do
    content_writers [
      {Writers::HTMLWriter => :publishers},
      {Writers::PageWriter => :publishers}
    ]

    publishers [
      Publishers::Rsyncer
    ]
  end
end
```

We fire off just the `HTMLWriter`:

```ruby
Pipes.enqueue(Writer::HTMLWriter, 'en-US')
```

Pipes queues up the `Writer::HTMLWriter` and its dependent, `Publishers::Rsyncer`. So, our queue looks like this:

```ruby
# Stage 1 (content_writers)
Writers::HTMLWriter.perform('en-US')

# Stage 2 (publishers)
Publishers::Rsyncer.perform('en-US')
```

After processing the first job, `HTMLWriter`, the Pipes queue looks like this:

```ruby
# Stage 1 (content_writers)
Writers::PageWriter.perform(1, 'en-US')
Writers::PageWriter.perform(2, 'en-US')
Writers::PageWriter.perform(3, 'en-US')
...

# Stage 2 (publishers)
Publishers::Rsyncer.perform('en-US')
```

Pipes will ensure your stages stay intact when enqueueing additional jobs mid-pipe. That is, **Stage 2** jobs are still queued *after* additional jobs have been added to **Stage 1**. This applies to jobs added to any stages. You can continue to add jobs to any stage while Pipes is working.

**The allow_duplicates option**

By default, Pipes will check for exact duplicate jobs in the queue (eg `Writer::HTMLWriter` with argument `en-US`). If we don't provide the `allow_duplicates` option within the `HTMLWriter`'s `#perform` method, the Pipes queue would look like this:

```ruby
# Stage 1 (content_writers)
(DONE) Writers::HTMLWriter.perform('en-US')
Writers::PageWriter.perform(1, 'en-US')
Writers::PageWriter.perform(2, 'en-US')
Writers::PageWriter.perform(3, 'en-US')
...

# Stage 2 (publishers)
Publishers::Rsyncer.perform('en-US')
Publishers::Rsyncer.perform(1, 'en-US')
Publishers::Rsyncer.perform(2, 'en-US')
Publishers::Rsyncer.perform(3, 'en-US')
```

We only want to run rsync once, so this is incorrect. To prevent this from happening, we indicate that we only want duplicate `:content_writers` to the **allow_duplicates** option.

By telling Pipes that we want to only allow duplicate `:content_writers`, we prevent duplicate `Rsyncer`s from being queued up, even though `PageWriter` has a `Rsyncer` dependency. **allow_duplicates** will force Pipes to check whether the `Rsyncer` class already exists in the queue (ignoring job arguments), and if so, skips that job.

## Support

Pipes makes use of Ruby 1.9's ordered hashes. No deliberate support for Ruby 1.8.

## Known Caveats

If your job is expecting a hash as the last argument, you'll need to pass an additional hash so pipes won't think your final argument is the options:

```ruby
# Pipes will assume {follow_links: true} is options for Pipes, not your job:
Pipes.enqueue([Writers::HTMLWriter], {follow_links: true})

# So you should pass a trailing hash to denote that there are no Pipes options:
Pipes.enqueue([Writers::HTMLWriter], {follow_links: true}, {})

# Of course, if you do specify options for Pipes, everything will work fine:
Pipes.enqueue([Writers::HTMLWriter], {follow_links: true}, {resolve: true})
```

## Future Improvements

- Better atomicity
- Represent jobs and stages as objects, instead of simple data structures
- Support for runaway workers/jobs
- Tab in Resque status site.

## Credits

![Factory Code Labs](http://i.imgur.com/yV4u1.png)

Pipes is maintained by [Factory Code Labs](http://www.factorycodelabs.com).

## License

Pipes is Copyright © 2012 Factory Code Labs. It is free software, and may be redistributed under the terms specified in the MIT-LICENSE file.