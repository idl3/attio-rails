# Attio Rails

[![Documentation](https://img.shields.io/badge/docs-yard-blue.svg)](https://idl3.github.io/attio-rails)
[![Gem Version](https://badge.fury.io/rb/attio-rails.svg)](https://badge.fury.io/rb/attio-rails)
[![CI](https://github.com/idl3/attio-rails/actions/workflows/ci.yml/badge.svg)](https://github.com/idl3/attio-rails/actions/workflows/ci.yml)

Rails integration for the [Attio](https://github.com/idl3/attio) Ruby client. This gem provides Rails-specific features including ActiveRecord model synchronization, generators, and background job integration.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'attio-rails', '~> 0.1.0'
```

And then execute:

```bash
bundle install
rails generate attio:install
```

## Configuration

After running the install generator, configure Attio in `config/initializers/attio.rb`:

```ruby
Attio::Rails.configure do |config|
  config.api_key = ENV['ATTIO_API_KEY']
  config.async = true  # Use ActiveJob for syncing
  config.queue = :default  # ActiveJob queue name
  config.logger = Rails.logger
end
```

## Usage

### ActiveRecord Integration

Add the `Attio::Rails::Syncable` concern to your models:

```ruby
class User < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'people',
                 attributes: [:email, :first_name, :last_name],
                 identifier: :email
  
  # Optional callbacks
  before_attio_sync :prepare_data
  after_attio_sync :log_sync
  
  private
  
  def prepare_data
    # Prepare data before syncing
  end
  
  def log_sync(response)
    Rails.logger.info "Synced to Attio: #{response['id']}"
  end
end
```

### Manual Syncing

```ruby
# Sync a single record
user = User.find(1)
user.sync_to_attio

# Sync multiple records
User.where(active: true).find_each(&:sync_to_attio)

# Async sync (requires ActiveJob)
user.sync_to_attio_later
```

### Custom Field Mapping

```ruby
class Company < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'companies',
                 attributes: {
                   name: :company_name,
                   domain: :website_url,
                   employee_count: ->(c) { c.employees.count }
                 },
                 identifier: :domain
end
```

### Batch Operations

```ruby
# Sync multiple records efficiently
Attio::Rails::BatchSync.perform(
  User.where(updated_at: 1.day.ago..),
  object: 'people'
)
```

### ActiveJob Integration

The gem automatically uses ActiveJob for background syncing when configured:

```ruby
class User < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'people', async: true
  
  # Automatically syncs in background after save
  after_commit :sync_to_attio_later
end
```

### Generator

The install generator creates:
- Configuration initializer at `config/initializers/attio.rb`
- ActiveJob class at `app/jobs/attio_sync_job.rb`
- Migration for tracking sync status (optional)

```bash
rails generate attio:install
rails generate attio:install --skip-job  # Skip job creation
rails generate attio:install --skip-migration  # Skip migration
```

## Advanced Features

### Conditional Syncing

```ruby
class User < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'people',
                 if: :should_sync_to_attio?
  
  def should_sync_to_attio?
    confirmed? && !deleted?
  end
end
```

### Error Handling

```ruby
class User < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'people',
                 on_error: :handle_sync_error
  
  def handle_sync_error(error)
    Rails.logger.error "Attio sync failed: #{error.message}"
    Sentry.capture_exception(error)
  end
end
```

### Custom Transformations

```ruby
class User < ApplicationRecord
  include Attio::Rails::Syncable
  
  attio_syncable object: 'people',
                 transform: :transform_for_attio
  
  def transform_for_attio(attributes)
    attributes.merge(
      full_name: "#{first_name} #{last_name}",
      tags: user_tags.pluck(:name)
    )
  end
end
```

## Testing

The gem includes RSpec helpers for testing:

```ruby
# In spec/rails_helper.rb
require 'attio/rails/rspec'

# In your specs
RSpec.describe User do
  include Attio::Rails::RSpec::Helpers
  
  it 'syncs to Attio' do
    user = create(:user)
    
    expect_attio_sync(object: 'people') do
      user.sync_to_attio
    end
  end
end
```

## Development

After checking out the repo:

```bash
bundle install
cd spec/dummy
rails db:create db:migrate
cd ../..
bundle exec rspec
```

To run tests against different Rails versions:

```bash
RAILS_VERSION=7.1 bundle update
bundle exec rspec

RAILS_VERSION=7.0 bundle update
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/idl3/attio-rails. Please read our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- 📖 [Documentation](https://idl3.github.io/attio-rails)
- 🐛 [Issues](https://github.com/idl3/attio-rails/issues)
- 💬 [Discussions](https://github.com/idl3/attio-rails/discussions)
- 📦 [Main Attio Gem](https://github.com/idl3/attio)