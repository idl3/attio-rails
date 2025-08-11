# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-01-11

### Added
- **BatchSync** class for efficient bulk synchronization operations
- **ActiveJob integration** with dedicated `AttioSyncJob` for background processing
- **Callbacks support** - `before_attio_sync` and `after_attio_sync` hooks
- **Transform support** - Custom attribute transformation before syncing
- **Error handlers** - Configurable error handling with `:on_error` option
- **RSpec test helpers** - Comprehensive testing utilities for Attio operations
- **Concepts documentation** - Detailed architecture guide with Mermaid diagrams
- **Configuration enhancements**:
  - `queue` option for ActiveJob queue configuration
  - `raise_on_missing_record` option for missing record behavior
- **100% test coverage** with comprehensive test suite

### Changed
- Enhanced `Syncable` concern with callbacks and transforms
- Improved error handling with environment-specific behavior
- Renamed GitHub Actions workflow from `release.yml` to `build-and-publish.yml`
- Updated README with comprehensive examples and usage patterns

### Fixed
- RuboCop linting issues for better code quality
- Test coverage gaps - achieved 100% coverage

## [0.1.2] - 2025-01-11

### Changed
- Updated attio dependency to 0.1.3
- Applied Stripe's RuboCop configuration
- Achieved 100% test coverage

### Fixed
- All RuboCop offenses auto-corrected
- Test failures resolved

## [0.1.1] - 2025-01-11

### Added
- Support for Ruby 3.4
- Support for Rails 8.0
- Missing test dependencies (webmock, pry, sqlite3)

### Fixed
- Fixed namespace loading issue with Concerns::Syncable module
- Fixed ActiveJob deprecation warning (exponentially_longer -> polynomially_longer)
- Fixed gem installation issues in CI

### Changed
- Updated RSpec to 3.13 for compatibility
- Improved CI workflow to test against Ruby 3.4 and Rails 8.0

## [0.1.0] - 2025-01-11

### Added
- Initial release of Attio Rails integration gem
- ActiveRecord concern `Attio::Rails::Syncable` for model synchronization
- Rails generator for initial setup (`rails generate attio:install`)
- ActiveJob integration for async syncing
- Configuration management through Rails config
- Support for Rails 6.1, 7.0, and 7.1
- Comprehensive test suite with dummy Rails app
- Full documentation with YARD
- CI/CD setup with GitHub Actions

### Features
- Automatic syncing of ActiveRecord models to Attio
- Configurable attribute mapping
- Support for callbacks (before_sync, after_sync)
- Error handling and retry logic
- Batch operations support
- Custom field transformations

[Unreleased]: https://github.com/idl3/attio-rails/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/idl3/attio-rails/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/idl3/attio-rails/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/idl3/attio-rails/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/idl3/attio-rails/releases/tag/v0.1.0