# Attio Rails Setup

The Attio Rails gem has been installed and configured!

## Next Steps

1. Set your Attio API key in your environment variables:
   ```
   ATTIO_API_KEY=your_api_key_here
   ```

2. Add the Syncable concern to models you want to sync with Attio:
   ```ruby
   class User < ApplicationRecord
     include Attio::Rails::Concerns::Syncable
     
     syncs_with_attio 'users', {
       email: :email,
       name: :full_name,
       company: -> (user) { user.company.name }
     }
   end
   ```

3. Run migrations to add the attio_record_id column to your models:
   ```
   rails db:migrate
   ```

4. Your models will now automatically sync to Attio on create, update, and destroy!

## Manual Sync

You can also manually trigger syncs:
```ruby
user.sync_to_attio
```

For more information, visit: https://github.com/your-username/attio-ruby