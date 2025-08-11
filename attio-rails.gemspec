require_relative 'lib/attio/rails/version'

Gem::Specification.new do |spec|
  spec.name          = "attio-rails"
  spec.version       = Attio::Rails::VERSION
  spec.authors       = ["Ernest Sim"]
  spec.email         = ["ernest.codes@gmail.com"]

  spec.summary       = %q{Rails integration for the Attio API client}
  spec.description   = %q{Rails-specific features and integrations for the Attio Ruby client, including model concerns and generators}
  spec.homepage      = "https://github.com/idl3/attio-rails"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://idl3.github.io/attio-rails"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "attio", "~> 0.1", ">= 0.1.1"
  spec.add_dependency "rails", ">= 6.1", "< 8.0"

  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "redcarpet", "~> 3.5"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "simplecov-cobertura", "~> 2.1"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "danger", "~> 9.4"
end
