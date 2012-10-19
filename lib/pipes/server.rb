require 'resque/server'

if Pipes.resque_tab
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

            def self.tab_url
              Pipes.resque_tab_name.downcase
            end

            def tab_url
              Pipes.resque_tab_name.downcase
            end
          end

          get "/#{tab_url}" do
            erb local_template('pipes.erb')
          end

          get "/#{tab_url}.poll" do
            @polling = true
            erb local_template('pipes.erb'), {:layout => false}
          end

          post "/#{tab_url}/force_next" do
            Pipes::Store.remaining_jobs.clear
            Pipes::Store.next_stage
            redirect url_path("#{tab_url}")
          end

          post "/#{tab_url}/clear" do
            Pipes::Store.clear(params[:stage_name].to_sym)
            redirect url_path("#{tab_url}")
          end

          post "/#{tab_url}/clear_all" do
            Pipes::Store.clear_all
            redirect url_path("#{tab_url}")
          end
        end
      end

      Resque::Server.tabs << Pipes.resque_tab_name
    end
  end

  Resque::Server.class_eval do
    include Pipes::Server
  end
end