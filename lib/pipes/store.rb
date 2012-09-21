require 'redis/objects'
require 'redis/list'
require 'redis/counter'

module Pipes
  # Stages are stored in Redis in the following manner:
  # pipes:stages:stage_1 [{class: 'ContentWriterStrategy', args: ['en-US']}, ...]
  # pipes:stages:stage_2 [{class: 'PublisherStrategy', args: ['en-US']}]
  #
  # The jobs stored in Redis are Marshalled Ruby objects, so the structure is
  # more-or-less arbitrary, though at a performance cost.
  #
  # Jobs are queued up in the following steps
  #   1. Strategies in stage n? No, look in stage n+1 until last stage.
  #                             Yes, shift off the next stage and queue up its jobs
  #   2. Strategies run concurrently. Keep track of how many are currently running to
  #      know when the next stage should be started.
  #
  class Store

    # Add a new set of stages to Redis.
    #
    def self.add_pipe(stages, options = {})
      stages.each do |stage|
        stage[:jobs].each do |job|
          pending = pending_jobs(stage[:name])
          pending << job if valid_for_queue?(stage[:name], pending, job, options)
        end
      end
      next_stage
    end

    # Fire off the next available stage, if available.
    #
    def self.next_stage
      return unless remaining_jobs == 0

      # Always start at the first stage, in case new stragies have been added mid-pipe
      stages.each do |stage|
        if !(jobs = pending_jobs(stage)).empty?
          run_stage(jobs)
          clear(stage)
          return
        end
      end
    end

    # Actually enqueue the jobs.
    #
    def self.run_stage(jobs)
      remaining_jobs.clear
      remaining_jobs.incr(jobs.count)

      jobs.each do |job|
        Resque.enqueue(job[:class], *job[:args])
      end
    end

    # Register that a job has finished.
    #
    def self.done
      if remaining_jobs.decrement == 0
        next_stage
      end
    end

    # Clear a specific stage queue.
    #
    def self.clear(stage)
      pending_jobs(stage).clear
    end

    # Find all stage queues in Redis (even ones not configured), and clear them.
    #
    def self.clear_all
      stage_keys = Redis.current.keys "#{@redis_stages_key}:*"
      Redis.current.del *stage_keys unless stage_keys.empty?

      remaining_jobs.clear
    end

    private

    def self.valid_for_queue?(stage, pending, job, options)
      # allow_duplicates checks just the class for duplication
      if options[:allow_duplicates] and !Array(options[:allow_duplicates]).include?(stage)
        pending_classes = pending.map { |job| job[:class] }
        return false if pending_classes.include?(job[:class])
      end

      # Is this exact job already queued up?
      !pending.include?(job)
    end

    def self.stages
      StageParser.new.stage_names
    end

    def self.stage_key(name)
      "#{@redis_stages_key}:#{name}"
    end

    def self.pending_jobs(stage)
      Redis::List.new(stage_key(stage), marshal: true)
    end

    def self.remaining_jobs
      @remaining_jobs ||= Redis::Counter.new(@redis_remaining_key)
    end

    def self.namespace
      "#{Pipes.namespace + ':' if Pipes.namespace}#{@namespace}"
    end

    @namespace           = 'pipes'
    # All pending stages for the current job
    @redis_stages_key    = "#{namespace}:stages"
    # Remaining jobs to call .done, ie jobs still in the workers
    @redis_remaining_key = "#{namespace}:stage_remaining"

  end
end