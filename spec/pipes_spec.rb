require 'spec_helper'
require 'pipes'

describe Pipes do

  describe 'options' do
    [:namespace].each do |option|
      it "allows you to set #{option}" do
        Pipes.should respond_to(option)
        Pipes.should respond_to("#{option}=")
      end
    end
  end

  describe '.redis=' do

    it 'accepts a string' do
      connection = mock('Redis')
      Redis.should_receive(:new).with(host: 'myhost', port: '1337') { connection }
      Resque.should_receive(:redis=).with(connection)
      Redis.should_receive(:current=).with(connection)

      Pipes.redis = 'myhost:1337'
    end

    it 'accepts a redis connection' do
      connection = mock('Redis')
      Resque.should_receive(:redis=).with(connection)
      Redis.should_receive(:current=).with(connection)

      Pipes.redis = connection
    end

  end

  describe '.stages' do

    it 'forwards on configuration to Abyss' do
      config = Proc.new {}
      Abyss.should_receive(:configure).with(&config)
      Pipes.stages(&config)
    end

  end

  describe '.enqueue' do

    it 'delegates to Runner.run' do
      Pipes::Runner.should_receive(:run).with(Writers::ContentWriter, 'some arg', {resolve: true})
      Pipes.enqueue(Writers::ContentWriter, 'some arg', {resolve: true})
    end

  end

end