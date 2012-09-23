require 'spec_helper'

describe Pipes::Runner do

  describe '.run' do

    let(:jobs) { [Writers::ContentWriter, Writers::AnotherContentWriter, Publishers::Publisher] }
    let(:arg)  { 'en-US' }

    before do
      Pipes.configure do |config|
        config.stages do
          content_writers [{Writers::ContentWriter => :publishers}]
          publishers      [Publishers::Publisher]
        end
      end
    end

    context 'with dependency resolution turned off' do

      let(:options) { {resolve: false} }

      it 'adds a pipe for all the jobs and runs it, filtering out jobs that are not configured' do
        pipe = [
          {name: :content_writers, jobs: [{class: Writers::ContentWriter, args: [arg]}]},
          {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: [arg]}]}
        ]

        Pipes::Store.should_receive(:add_pipe).with(pipe, options)
        Pipes::Runner.run(jobs, arg, options)
      end

      it 'can be turned off in the config' do
        original = Pipes.resolve
        Pipes.resolve = false

        Pipes::Store.should_receive(:add_pipe).with([{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]}], {})
        Pipes::Runner.run(Writers::ContentWriter)

        Pipes.resolve = original
      end

      it 'accepts an array of strings of jobs' do
        Pipes::Store.should_receive(:add_pipe).with([{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]}], options)
        Pipes::Runner.run(['Writers::ContentWriter'], options)
      end

      it 'accepts an array of symbols referring to stages' do
        pipe = [
          {name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]},
          {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: []}]}
        ]

        Pipes::Store.should_receive(:add_pipe).with(pipe, options)
        Pipes::Runner.run([:content_writers, :publishers], options)
      end

      it 'accepts a singular class' do
        Pipes::Store.should_receive(:add_pipe).with([{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]}], options)
        Pipes::Runner.run(Writers::ContentWriter, options)
      end

      it 'accepts a singular string referring to a class' do
        Pipes::Store.should_receive(:add_pipe).with([{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]}], options)
        Pipes::Runner.run('Writers::ContentWriter', options)
      end

      it 'accepts a symbol referring to a stage' do
        Pipes::Store.should_receive(:add_pipe).with([{name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]}], options)
        Pipes::Runner.run(:content_writers, options)
      end

    end

    context 'with dependency resolution turned on' do

      let(:options) { {resolve: true} }
      let(:pipe) {
        [
          {name: :content_writers, jobs: [{class: Writers::ContentWriter, args: []}]},
          {name: :publishers,      jobs: [{class: Publishers::Publisher,  args: []}]}
        ]
      }

      it 'includes all dependencies of the provided job' do
        Pipes::Store.should_receive(:add_pipe).with(pipe, options)
        Pipes::Runner.run(Writers::ContentWriter, options)
      end

      it 'is the default' do
        Pipes::Store.should_receive(:add_pipe).with(pipe, {})
        Pipes::Runner.run(Writers::ContentWriter)
      end

      it 'can overwrite the value defined in the config' do
        original = Pipes.resolve
        Pipes.resolve = false

        Pipes::Store.should_receive(:add_pipe).with(pipe, options)
        Pipes::Runner.run(Writers::ContentWriter, options)

        Pipes.resolve = original
      end

    end

  end

end