require 'abyss'

module Pipes
  class StageParser
    def initialize(stages = nil)
      @stages = stages || Abyss.configuration.stages.configurations
      resolve_dependencies
    end

    # Grab all stage names.
    #
    def stage_names
      @stages.keys
    end

    # Grab all jobs for the given stage.
    #
    def jobs_in_stage(stage)
      array_for_stage(@stages[stage])
    end

    # Recursively grab dependencies for a given job.
    #
    def dependents_for(job)
      if !@dependencies[job] or @dependencies[job].empty?
        []
      else
        recursive_dependencies = @dependencies[job].map{ |klass| dependents_for(klass) }
        (@dependencies[job] + recursive_dependencies).flatten.uniq
      end
    end

    # Normalize configured stages so they have a consistent form.
    #
    # This will return a structure exactly the same as that defined in the config,
    # except, all the "magic" dependencies (symbols to other stages, references
    # to classes, and arrays of both) have been replaced with the name of the actual
    # dependency, ie the class.
    #
    # Further, each job has been converted to a hash, with the job as the
    # key and the dependencies as the the values.
    #
    # This data is normalized so that it can be used within the interface, and what
    # to do about the dependencies is up to the implementation.
    #
    def stages_with_resolved_dependencies
      # Looping over all stages...
      @stages.inject({}) do |resolved_stages, (name, jobs)|
        # If it's defined with a stage dependency
        jobs, _ = jobs.to_a.first if jobs.is_a? Hash

        # Looping over all jobs...
        resolved_stages[name] = jobs.inject([]) do |resolved_stage, job|
          job = job.keys[0] if job.is_a? Hash
          # Normalze to new hash form
          resolved_stage << {job => @dependencies[job]}
        end
        resolved_stages
      end
    end

    private

    # Populates @dependencies hash in the form of:
    # {
    #   SomeClass => [OtherClass, AnotherClass],
    #   ...
    # }
    # 
    # Loop over and resolve dependencies on a job-by-job basis.
    #
    # Work from the bottom up since dependencies can only be specified for
    # lower-priority stages (ie lower stages won't reference higher ones)
    #
    def resolve_dependencies
      @dependencies = {}

      reversed = Hash[@stages.to_a.reverse]
      reversed.each do |name, jobs|
        if jobs.is_a? Hash
          # Stage dependency present
          jobs, stage_dependents = jobs.to_a.first
        end

        jobs.each do |job|
          # Does the job have dependents?
          if job.is_a? Hash
            job, dependents = job.to_a.first
            @dependencies[job] = dependencies_for_job(dependents)
          else
            # Defined job is a simple class (eg Publisher)
            @dependencies[job] = []
          end

          if stage_dependents
            @dependencies[job] += dependencies_for_job(stage_dependents)
          end
        end
      end
    end

    # If the job has dependents, figure out how to resolve.
    #
    def dependencies_for_job(dependents)
      if dependents.is_a? Symbol
        # Referring to another stage (eg :publishers)
        dependents_for_stage(dependents)
      elsif dependents.is_a? Array
        # Referring to an array of dependencies (eg [:publishers, Publisher2])
        dependencies_from_array(dependents)
      else
        # Referring to another job (eg Publisher1)
        [dependents] + dependents_for(dependents)
      end
    end

    # Iterate over all jobs for this stage and find dependents.
    #
    def dependents_for_stage(stage_name)
      stage = array_for_stage(@stages[stage_name.to_sym])

      stage.inject([]) do |jobs, job|
        # Does the job have dependents?
        if job.is_a? Hash
          job, dependents = job.to_a.first
          jobs << job
          jobs << dependencies_for_job(dependents)
        else
          # Defined job is a simple class (eg Publisher)
          jobs << [job] + dependents_for(job)
        end
      end.flatten.uniq
    end

    # When dependencies are defined as an array, loop over the array and resolve.
    #
    def dependencies_from_array(dependents)
      # Referring to an array of dependents
      # Can be a mixed array (eg [:publishers, Publisher2])
      dependents.inject([]) do |klasses, dependent|
        if dependent.is_a? Symbol
          # Referring to an array of stages (eg [:publishers, :emailers])
          klasses << dependents_for_stage(dependent)
        else
          # Referring to an array of jobs (eg [Publisher1, Publisher2])
          klasses << [dependent] + dependents_for(dependent)
        end
      end.flatten.uniq
    end

    # Just list the jobs in the stage, ignoring dependencies.
    #
    def array_for_stage(jobs)
      jobs, _ = jobs.to_a.first if jobs.is_a? Hash

      jobs.inject([]) do |arr, job|
        arr << if job.is_a? Hash
          # Take just the job class, without any dependents
          job.keys[0]
        else
          job
        end
      end
    end
  end
end