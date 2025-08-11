# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/idl3/attio-rails/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/idl3/attio-rails/releases/tag/v0.1.0