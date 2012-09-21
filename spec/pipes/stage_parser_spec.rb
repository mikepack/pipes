require 'spec_helper'
require 'mock_jobs'

describe Pipes::StageParser do
  subject { Pipes::StageParser }

  describe '#stage_names' do
    it 'returns the name of the stages, in the same order' do
      stages = {
                 writers:    [ Writers::ContentWriter ],
                 publishers: [ Publishers::Publisher ]
               }

      subject.new(stages).stage_names.should == [:writers, :publishers]
    end
  end

  describe '#jobs_in_stage' do
    it 'returns all jobs for a given stage, without dependents' do
      stages = {
                 writers:    [ { Writers::ContentWriter => Publishers::Publisher } ],
                 publishers: [ Publishers::Publisher ]
               }

      subject.new(stages).jobs_in_stage(:writers).should == [Writers::ContentWriter]
    end
  end

  describe '#dependents_for' do
    let(:stages) {
      {
        writers:    [ { Writers::ContentWriter => :publishers } ],
        publishers: [ Publishers::Publisher => Emailers::Email ],
        emailers:   [ Emailers::Email ]
      }
    }

    it 'returns an empty array for jobs that do not exist' do
      subject.new(stages).dependents_for(Writers::AnotherContentWriter).should == []
    end

    it 'returns an array containing the recursive dependents' do
      expected = [Publishers::Publisher, Emailers::Email]

      subject.new(stages).dependents_for(Writers::ContentWriter).should == expected
    end
  end

  describe '#stages_with_resolved_dependencies' do
    context 'when the stage contains only job classes' do
      let(:stages) {
        {
          writers:    [ Writers::ContentWriter ],
          publishers: [ Publishers::Publisher ]
        }
      }

      it 'returns a set of nested arrays, keeping the defined order, each representing a stage and its jobs with empty dependents' do
        expected = {
                     writers:    [ { Writers::ContentWriter => [] } ],
                     publishers: [ { Publishers::Publisher => [] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end

    context 'when the stage containing a hash defining a dependent class' do
      let(:stages) {
        { writers: [ { Writers::ContentWriter => Publishers::Publisher } ] }
      }

      it 'adds the dependent class to the list' do
        expected = {
                     writers: [ { Writers::ContentWriter => [Publishers::Publisher] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end

    context 'with the stage containing a hash defining a dependent stage' do
      let(:stages) {
        {
          writers:    [ { Writers::ContentWriter => :publishers } ],
          publishers: [ Publishers::Publisher ]
        }
      }

      it 'adds all classes within the dependent stage to the list' do
        expected = {
                     writers:    [ { Writers::ContentWriter => [Publishers::Publisher] } ],
                     publishers: [ { Publishers::Publisher  => [] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end

    context 'with the stage containing a hash defining an array of dependent classes' do
      let(:stages) {
        {
          writers:    [ { Writers::ContentWriter => [Publishers::Publisher] } ],
          publishers: [ Publishers::Publisher ]
        }
      }

      it 'adds all classes within the array to the list' do
        expected = {
                     writers:    [ { Writers::ContentWriter => [Publishers::Publisher] } ],
                     publishers: [ { Publishers::Publisher  => [] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end

    context 'with the stage containing a hash defining an array of dependent stages' do
      let(:stages) {
        {
          writers:    [ { Writers::ContentWriter => [:publishers] } ],
          publishers: [ Publishers::Publisher ]
        }
      }

      it 'adds all classes within the dependent stages to the list' do
        expected = {
                     writers:    [ { Writers::ContentWriter => [Publishers::Publisher] } ],
                     publishers: [ { Publishers::Publisher  => [] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end

    context 'with a comlex configuration, intermixing dependent types' do
      let (:stages) {
        {
          writers:    [ { Writers::ContentWriter        => [:publishers, Uploaders::Rsync] },
                        { Writers::AnotherContentWriter => [Emailers::Email] }
                      ],
          publishers: [ { Publishers::Publisher => :emailers } ],
          messengers: [ { Messengers::SMS => :uploaders } ],
          uploaders:  [ { Uploaders::Rsync => Notifiers::Twitter } ],
          emailers:   [ Emailers::Email, Emailers::AnotherEmail ],
          notifiers:  [ Notifiers::Twitter ]
        }
      }

      it 'resolves all dependencies' do
        expected = {
                     writers:    [ { Writers::ContentWriter        => [Publishers::Publisher, Emailers::Email, Emailers::AnotherEmail,
                                                                       Uploaders::Rsync, Notifiers::Twitter] },
                                   { Writers::AnotherContentWriter => [Emailers::Email] }
                                 ],
                     publishers: [ { Publishers::Publisher  => [Emailers::Email, Emailers::AnotherEmail] } ],
                     messengers: [ { Messengers::SMS        => [Uploaders::Rsync, Notifiers::Twitter] } ],
                     uploaders:  [ { Uploaders::Rsync       => [Notifiers::Twitter] } ],
                     emailers:   [ { Emailers::Email        => [] },
                                   { Emailers::AnotherEmail => [] }
                                 ],
                     notifiers:  [ { Notifiers::Twitter     => [] } ]
                   }

        subject.new(stages).stages_with_resolved_dependencies.should == expected
      end
    end
  end
end