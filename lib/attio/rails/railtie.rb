module Attio
  module Rails
    class Railtie < ::Rails::Railtie
      initializer "attio.configure_rails_initialization" do
        ActiveSupport.on_load(:active_record) do
          require 'attio/rails/concerns/syncable'
        end
      end

      generators do
        require 'generators/attio/install/install_generator'
      end
    end
  end
end