require 'pipes'
require 'resque'

Resque.before_fork do |job|
  job.payload_class.extend Pipes::ResqueHooks
end

module Pipes
  module ResqueHooks
    def after_perform_pipes(*args)
      Pipes::Store.done
    end

    def on_failure_pipes(e, *args)
      Pipes::Store.done
    end
  end
end