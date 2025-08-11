require 'rails/generators/base'

module Attio
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      
      class_option :skip_job, type: :boolean, default: false, desc: "Skip creating the sync job"
      class_option :skip_migration, type: :boolean, default: false, desc: "Skip creating the migration"

      def check_requirements
        unless defined?(ActiveJob)
          say "Warning: ActiveJob is not available. Skipping job creation.", :yellow
          @skip_job = true
        end
      end

      def create_initializer
        template 'attio.rb', 'config/initializers/attio.rb'
      end

      def create_migration
        return if options[:skip_migration]
        
        if defined?(ActiveRecord)
          migration_template 'migration.rb', 'db/migrate/add_attio_record_id_to_tables.rb'
        else
          say "ActiveRecord not detected. Skipping migration.", :yellow
        end
      end

      def create_sync_job
        return if options[:skip_job] || @skip_job
        
        template 'attio_sync_job.rb', 'app/jobs/attio_sync_job.rb'
      end

      def add_to_gemfile
        gem_group :production do
          gem 'attio-rails'
        end unless gemfile_contains?('attio-rails')
      end

      def display_readme
        readme 'README.md'
      end

      private

      def gemfile_contains?(gem_name)
        File.read('Gemfile').include?(gem_name)
      rescue
        false
      end

      def rails_version
        Rails::VERSION::STRING
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end