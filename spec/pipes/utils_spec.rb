require 'spec_helper'
require 'pipes/utils'

describe Pipes::Utils do
  describe '.constantize' do
    it 'converts strings to constants' do
      subject.constantize('Pipes::Utils').should == Pipes::Utils
    end

    it 'does not bail when fetching constants from root' do
      subject.constantize('::Pipes::Utils').should == Pipes::Utils
    end
  end
end