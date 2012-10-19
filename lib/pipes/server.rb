require 'resque/server'

module Pipes
  module Server
    def self.included(base)
      base.class_eval do
        helpers do
          def local_template(path)
            File.read(File.join(File.dirname(__FILE__), "server/views/#{path}"))
          end

          def titleize(stage)
            stage.to_s.split('_').each(&:capitalize!).join(' ')
          end
        end

        get "/pipes" do
          erb local_template('pipes.erb')
        end

        get "/pipes.poll" do
          @polling = true
          erb local_template('pipes.erb'), {:layout => false}
        end

        post "/pipes/force_next" do
          Pipes::Store.remaining_jobs.clear
          Pipes::Store.next_stage
          redirect url_path("pipes")
        end

        post "/pipes/clear" do
          Pipes::Store.clear(params[:stage_name].to_sym)
          redirect url_path("pipes")
        end

        post "/pipes/clear_all" do
          Pipes::Store.clear_all
          redirect url_path("pipes")
        end
      end
    end

    Resque::Server.tabs << 'Pipes'
  end
end

Resque::Server.class_eval do
  include Pipes::Server
end