require 'spec_helper'
require 'mock_jobs'

describe Pipes::Store do

  def mock_stages
    Pipes::Store.stub!(:stages) { stages }
    stages
  end

  def mock_pending_jobs(stage)
    list = send("pending_jobs_#{stage}".to_sym)
    Pipes::Store.stub!(:pending_jobs).with(stage) { list }
    list
  end

  let(:stages) { [] }
  let(:pending_jobs_content_writers) { [] }
  let(:pending_jobs_publishers)      { [] }

  let(:job_options) { 'en-US' }
  let(:pipe)        { [{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: [job_options]}]},
                       {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: [job_options]}]}] }

  before do
    Pipes::Store.clear_all
  end

  describe '.add_pipe' do
    before do
      @writers = mock_pending_jobs(:content_writers)
      @publishers = mock_pending_jobs(:publishers)
      Pipes::Store.stub!(:next_stage)
    end

    it 'adds the job to Redis and fires off the next available stage' do
      Pipes::Store.should_receive(:next_stage)
      Pipes::Store.add_pipe(pipe)

      @writers.should == [{class: Writers::ContentWriter, args: [job_options]}]
      @publishers.should == [{class: Publishers::Publisher,  args: [job_options]}]
    end

    it 'does not add duplicate jobs to stages' do
      another_pipe = [{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: [job_options]},
                                                      {class: Writers::AnotherContentWriter, args: [job_options]}]},
                      {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: [job_options]}]}]

      Pipes::Store.add_pipe(pipe)
      Pipes::Store.add_pipe(another_pipe)

      @writers.should == [{class: Writers::ContentWriter, args: [job_options]}, {class: Writers::AnotherContentWriter, args: [job_options]}]
      @publishers.should == [{class: Publishers::Publisher,  args: [job_options]}]
    end

    context 'with allow_duplicates set' do
      it 'does not add jobs that have the same class already in the queue' do
        mock_stages

        Pipes::Store.add_pipe(pipe)

        @writers.should_receive(:<<)
        @publishers.should_not_receive(:<<)

        another_pipe = [{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: ['some arg']}]},
                        {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: ['some arg']}]}]

        Pipes::Store.add_pipe(another_pipe, {allow_duplicates: [:content_writers]})
      end
    end

  end

  describe '.next_stage' do
    context 'with jobs left in the queue' do
      it 'pulls the next stage with pending jobs off the queue and runs it' do
        Pipes::Store.stub!(:stages) { [:content_writers, :publishers] }

        writers = mock_pending_jobs(:content_writers) << {class: Writers::ContentWriter, args: []}
        publishers = mock_pending_jobs(:publishers) << {class: Publishers::Publisher,  args: []}

        Pipes::Store.should_receive(:run_stage).with([{class: Writers::ContentWriter, args: []}])
        Pipes::Store.should_not_receive(:run_stage).with([{class: Publishers::Publisher, args: []}])

        Pipes::Store.next_stage
      end

      it 'runs stages in the order determined by the stages list' do
        Pipes::Store.stub!(:stages) { [:publishers, :content_writers] }

        writers = mock_pending_jobs(:content_writers) << {class: Writers::ContentWriter, args: []}
        publishers = mock_pending_jobs(:publishers) << {class: Publishers::Publisher,  args: []}

        Pipes::Store.should_not_receive(:run_stage).with([{class: Writers::ContentWriter, args: []}])
        Pipes::Store.should_receive(:run_stage).with([{class: Publishers::Publisher, args: []}])

        Pipes::Store.next_stage
      end
    end

    context 'without jobs left in the queue' do
      it 'fires off the next pipe' do
        mock_stages
        Pipes::Store.should_not_receive(:run_stage)
        Pipes::Store.next_stage
      end
    end
  end

  describe '.run_stage' do
    it 'sets the remaining counter and enqueues the jobs' do
      stage = [{class: Writers::ContentWriter, args: [job_options]},
               {class: Writers::AnotherContentWriter, args: [job_options]}]

      remaining = mock('Remaining Jobs')
      Pipes::Store.stub!(:remaining_jobs) { remaining }

      remaining.should_receive(:clear)
      remaining.should_receive(:incr).with(2)

      Resque.should_receive(:enqueue).with(Writers::ContentWriter, 'en-US')
      Resque.should_receive(:enqueue).with(Writers::AnotherContentWriter, 'en-US')

      Pipes::Store.run_stage(stage)
    end
  end

  describe '.done' do
    context 'as the last job in a stage' do
      it 'fires off the next stage' do
        remaining = mock('Remaining Jobs', {decrement: 0}) { 1 }
        Pipes::Store.stub!(:remaining_jobs) { remaining }

        Pipes::Store.should_receive(:next_stage)
        Pipes::Store.done
      end
    end

    context 'with jobs still running' do
      it 'decrements the remaining jobs but does not run the next stage' do
        remaining = mock('Remaining Jobs') { 2 }
        Pipes::Store.stub!(:remaining_jobs) { remaining }

        remaining.should_receive(:decrement) { 1 }
        Pipes::Store.should_not_receive(:next_stage)
        Pipes::Store.done
      end
    end
  end

  describe '.clear' do
    it 'clears out the jobs for the given stage' do
      writers = mock_pending_jobs(:content_writers)
      writers << {class: Writers::ContentWriter, args: [job_options]}

      Pipes::Store.clear(:content_writers)
      writers.should == []
    end
  end

  describe '.clear_all' do
    it 'deletes Redis keys for all stages, even those not currently being used' do
      Redis::List.new('pipes:stages:some_stage_used_for_testing') << 'stategy'
      Redis::List.new('pipes:stages:any_stage_test') << 'stategy'

      Pipes::Store.clear_all

      Redis::List.new('pipes:stages:some_stage_used_for_testing').should == []
      Redis::List.new('pipes:stages:any_stage_test').should == []
    end

    it 'resets the remaining jobs counter' do
      remaining = mock('Remaining Jobs')
      Pipes::Store.stub!(:remaining_jobs) { remaining }

      remaining.should_receive(:clear)

      Pipes::Store.clear_all
    end
  end
end