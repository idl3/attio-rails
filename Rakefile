require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "yard"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']
  t.options = ['--markup-provider=redcarpet', '--markup=markdown', '--protected', '--private']
  t.stats_options = ['--list-undoc']
end

namespace :yard do
  desc "Generate documentation and serve it with live reloading"
  task :server do
    sh "bundle exec yard server --reload"
  end
  
  desc "Generate documentation for GitHub Pages"
  task :gh_pages do
    sh "bundle exec yard --output-dir docs"
    # Create .nojekyll file for GitHub Pages
    File.open("docs/.nojekyll", "w") {}
  end
end

task :default => [:spec, :rubocop]
