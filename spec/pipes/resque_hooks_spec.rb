require 'spec_helper'
require 'pipes/resque_hooks'

describe Pipes::ResqueHooks do
  class ResqueWorker
    extend Pipes::ResqueHooks
  end

  describe '.after_perform_pipes' do
    it 'lets the Redis store know it is finished working' do
      Pipes::Store.should_receive(:done)
      ResqueWorker.after_perform_pipes
    end
  end

  describe '.on_failure_pipes' do
    it 'clears the current job, forfeiting any remaining stages' do
      Pipes::Store.should_receive(:done)
      ResqueWorker.on_failure_pipes(Exception.new)
    end
  end
end