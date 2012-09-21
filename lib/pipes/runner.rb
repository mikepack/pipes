module Pipes
  # This is the entry point to running jobs.
  #
  # In most cases, this is the sole API used to start up some jobs and run
  # a series of stages (a pipe).
  #
  class Runner

    # Entry point to begin running jobs.
    #
    # eg, Pipes::Runner.run(MyStrategies::ContentWriter)
    #       ie, You want to run a single job from somewhere in the app.
    #     Pipes::Runner.run('MyStrategies::ContentWriter')
    #       ie, Params were passed for a single job 
    #     Pipes::Runner.run([MyStrategies::ContentWriter, YourStrategies::Publisher])
    #       ie, You want to run multiple jobs from somewhere in the app.
    #     Pipes::Runner.run(['MyStrategies::ContentWriter', 'YourStrategies::Publisher'])
    #       ie, Params were passed for multiple jobs
    #     Pipes::Runner.run(:content_writers)
    #       ie, You want to run an entire stage
    #     Pipes::Runner.run([:content_writers, :publishers])
    #       ie, You want to run multiple stages
    #
    def self.run(jobs, *args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      self.new(jobs, args, options)
    end

    # Set up the runner.
    #
    def initialize(jobs, job_args, options)
      @job_args, @options = job_args, options

      @requested = normalize_jobs(jobs)

      # Resolve if the option has been explicitly passed or it's specified in the config.
      if @options[:resolve] or (@options[:resolve] != false and Pipes.resolve)
        @requested = include_dependencies(@requested)
      end

      Store.add_pipe(construct_pipe, options)
    end

    private

    # Normalize requested jobs into an array of classes.
    #
    def normalize_jobs(jobs)
      if jobs.is_a?(Array)
        jobs.map { |job| normalize_job(job) }
      else
        [normalize_job(jobs)]
      end.flatten
    end

    # Normalize requested job, based on type requested
    #
    def normalize_job(job)
      if job.is_a?(String)
        Utils.constantize(job)
      elsif job.is_a?(Symbol)
        stage_parser.jobs_in_stage(job)
      else
        job
      end
    end

    # Given a list of jobs, include dependencies of those jobs in
    # the returned array.
    #
    def include_dependencies(jobs)
      jobs.inject([]) do |resolved, job|
        resolved << [job] + stage_parser.dependents_for(job)
      end.flatten
    end

    # Filter jobs by only the ones being requested and build out the pipe
    # array, including options.
    #
    def construct_pipe
      # Of all the stages listed in the config...
      stages.inject([]) do |filtered_stages, (stage_name, jobs)|
        filtered = filtered_jobs(stage_parser.jobs_in_stage(stage_name))

        # Add it unless all jobs have been filtered out
        if !filtered.empty?
          filtered_stages << {name: stage_name, jobs: filtered}
        else; filtered_stages; end
      end
    end

    # Construct an array of jobs that have been requested.
    #
    def filtered_jobs(jobs)
      jobs.inject([]) do |filtered_jobs, registered_job|
        # Is the configured job being requested for this pipe?
        if @requested.include?(registered_job)
          filtered_jobs << {class: registered_job, args: @job_args}
        else; filtered_jobs; end
      end
    end

    def stage_parser
      @parser ||= StageParser.new
    end

    def stages
      @stages ||= stage_parser.stages_with_resolved_dependencies
    end

  end
end