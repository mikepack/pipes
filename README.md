# Pipes [<img src="https://secure.travis-ci.org/mikepack/pipes.png" />](http://travis-ci.org/mikepack/pipes) [<img src="https://codeclimate.com/badge.png" />](https://codeclimate.com/github/mikepack/pipes)

![Pipes](http://i.imgur.com/MND26.png)

Pipes is a Redis-backed concurrency management system designed around Resque. It provides a DSL for defining "stages" of a process. Each (Resque) job in the stage can be run concurrently, but all must finish before subsequent stages are run.

## Example

At Factory Code Labs, we work on a system for which we must deploy static HTML files. We must render any number of HTML pages, assets, .htaccess files, etc so the static HTML-based site can run on Apache.

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

Once your configuration is set up, you can fire off the jobs:

```ruby
Pipes::Runner.run([Writers::HTMLWriter, Publishers::Rsyncer])
```

The above line essentially says "here's the jobs I'm looking to run", at which point Pipes takes over to determine how to partition them into their appropriate stages. Pipes will break these two jobs up as you would expect:

```ruby
# Stage 1 (content_writers)
Writers::HTMLWriter

# Stage 2 (publishers)
Publishers::Rsyncer
```

You can also pass arguments to the jobs, just like Resque:

```ruby
Pipes::Runner.run([Writers::HTMLWriter], 'http://localhost:3000/page')
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

Pipes::Runner.run([Writers::HTMLWriter], 'google.com', 80)
```

## Defining Stage Dependencies

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
Pipes::Runner.run([Writers::HTMLWriter], 'http://localhost:3000/page')
```

The above code will run `Writers::HTMLWriter` in **Stage 1**, `Publishers::Rsyncer` and `Publishers::CDNUploader` in **Stage 2**, and `Notifiers::FileActivator` in **Stage 3**, all receiving the `http://localhost:3000/page' argument.

You can turn off dependency resolution by passing in some additional Pipes options as the third argument:

```ruby
Pipes::Runner.run([Writers::HTMLWriter], 'http://localhost:3000/page', {resolve: false})
```

In the above code, only `Writers::HTMLWriter` will be run.

## Acceptable Formats for Jobs

Pipes allows you to specify your jobs in a variety of ways:

```ruby
# A single job
Pipes::Runner.run(Writers::HTMLWriter)

# A single job as a string. Might be helpful if accepting params from a form
Pipes::Runner.run('Writers::HTMLWriter')

# An entire stage
Pipes::Runner.run(:content_writers)

# You can pass an array of any of the above, intermixing types
Pipes::Runner.run([:content_writers, 'Publishers::CDNUploader', Notifiers::FileActivator])
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

  # config.resolve tells Pipes to resolve dependencies when calling Pipes::Runner.run(...) (default true):
  config.resolve = false

  config.stages do
    # ...
  end
end
```

If you're using Pipes in a Rails app, stick your configuration in `config/initializers/pipes.rb`.

## Support

Pipes is currently tested under Ruby 1.9.3.

## Known Caveats

If your job is expecting a hash as the last argument, you'll need to pass an additional hash so pipes won't think your final argument is the options:

```ruby
# Pipes will assume {follow_links: true} is options for Pipes, not your job:
Pipes::Runner.run([Writers::HTMLWriter], {follow_links: true})

# So you should pass a trailing hash to denote that there are no Pipes options:
Pipes::Runner.run([Writers::HTMLWriter], {follow_links: true}, {})

# Of course, if you do specify options for Pipes, everything will work fine:
Pipes::Runner.run([Writers::HTMLWriter], {follow_links: true}, {resolve: true})
```

## Future Improvements

- Better atomicity
- Represent jobs and stages as objects, instead of simple data structures
- Support for runaway workers/jobs

## Credits

![Factory Code Labs](http://i.imgur.com/yV4u1.png)

Pipes is maintained by [Factory Code Labs](http://www.factorycodelabs.com).

## License

Pipes is Copyright © 2012 Factory Code Labs. It is free software, and may be redistributed under the terms specified in the MIT-LICENSE file.