# Contributing to Attio Rails

Thank you for your interest in contributing to the Attio Rails integration gem! This guide will help you get started.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Testing with Rails](#testing-with-rails)
- [Submitting Changes](#submitting-changes)
- [Rails-Specific Guidelines](#rails-specific-guidelines)

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/attio-rails.git
   cd attio-rails
   ```
3. Add the upstream remote:
   ```bash
   git remote add upstream https://github.com/idl3/attio-rails.git
   ```

## Development Setup

1. Install Ruby 3.0 or higher
2. Install dependencies:
   ```bash
   bundle install
   ```
3. Set up the test Rails app:
   ```bash
   cd spec/dummy
   bundle install
   rails db:create db:migrate
   cd ../..
   ```
4. Run tests:
   ```bash
   bundle exec rspec
   ```

### Testing Different Rails Versions

To test with different Rails versions:

```bash
# Test with Rails 7.1
RAILS_VERSION=7.1 bundle update
bundle exec rspec

# Test with Rails 7.0
RAILS_VERSION=7.0 bundle update
bundle exec rspec

# Test with Rails 6.1
RAILS_VERSION=6.1 bundle update
bundle exec rspec
```

## Testing with Rails

### Writing Rails-Specific Tests

When adding new features, ensure you test:

1. **Generator Tests**: If adding generators
   ```ruby
   require "generators/attio/install/install_generator"
   
   RSpec.describe Attio::Generators::InstallGenerator do
     # Test generator behavior
   end
   ```

2. **Model Concern Tests**: For ActiveRecord integrations
   ```ruby
   RSpec.describe "Attio::Rails::Syncable" do
     let(:model) { User.new }
     # Test concern behavior
   end
   ```

3. **Railtie Tests**: For Rails integration points
   ```ruby
   RSpec.describe Attio::Rails::Railtie do
     # Test Rails configuration
   end
   ```

### Testing with Dummy Rails App

The gem includes a dummy Rails app in `spec/dummy` for integration testing:

```bash
cd spec/dummy
rails console  # Test your changes interactively
rails server   # Run the dummy app
```

## Submitting Changes

### Before Submitting

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following Rails conventions

3. Write or update tests

4. Update documentation

5. Run the full test suite:
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```

6. Update CHANGELOG.md

### Commit Messages

Use conventional commits:
- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation
- `test:` Test changes
- `chore:` Maintenance

Examples:
```
feat: add ActiveJob integration for async syncing
fix: handle Rails 7.1 deprecations
docs: add Rails 6.1 migration guide
```

## Rails-Specific Guidelines

### Following Rails Conventions

1. **Generators**: Follow Rails generator conventions
   - Use Thor for generator implementation
   - Provide clear descriptions
   - Support Rails conventions (--skip flags, etc.)

2. **Concerns**: Design reusable concerns
   - Keep concerns focused and single-purpose
   - Document required methods
   - Provide clear examples

3. **Configuration**: Use Rails configuration patterns
   ```ruby
   Rails.application.configure do
     config.attio.api_key = ENV['ATTIO_API_KEY']
   end
   ```

4. **ActiveRecord Integration**:
   - Follow ActiveRecord callback conventions
   - Support Rails validations
   - Integrate with Rails error handling

### Rails Version Compatibility

- Maintain compatibility with Rails 6.1+
- Test against multiple Rails versions
- Document version-specific features
- Handle deprecations gracefully

### Performance Considerations

- Use Rails caching when appropriate
- Leverage ActiveJob for background processing
- Optimize database queries
- Consider connection pooling

## Code Organization

```
lib/
├── attio/
│   ├── rails.rb              # Main module
│   ├── rails/
│   │   ├── version.rb         # Version constant
│   │   ├── railtie.rb         # Rails integration
│   │   ├── configuration.rb   # Config management
│   │   └── concerns/          # Model concerns
│   │       └── syncable.rb
└── generators/                # Rails generators
    └── attio/
        └── install/
            ├── install_generator.rb
            └── templates/
```

## Testing Requirements

- Write tests for all new features
- Maintain test coverage above 85%
- Test with multiple Rails versions
- Include integration tests with dummy app
- Test generators with Rails test helpers

## Documentation

### YARD Documentation

Document Rails-specific features:

```ruby
# Syncs the model with Attio
#
# @example Basic usage
#   class User < ApplicationRecord
#     include Attio::Rails::Syncable
#     
#     attio_syncable object: 'people',
#                    attributes: [:email, :name]
#   end
#
# @param options [Hash] sync configuration
# @option options [String] :object Attio object type
# @option options [Array] :attributes Attributes to sync
def attio_syncable(**options)
  # implementation
end
```

## Getting Help

- Check [Rails Guides](https://guides.rubyonrails.org/) for Rails conventions
- Review the [main Attio gem](https://github.com/idl3/attio) documentation
- Open an issue for questions
- Join discussions on GitHub

Thank you for contributing to Attio Rails!