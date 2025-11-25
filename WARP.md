# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Brainpipe is a Ruby gem. The codebase follows standard Ruby gem conventions with a minimal structure.

## Project Structure

```
lib/
  brainpipe.rb          # Main module entry point
  brainpipe/
    version.rb          # Version constant
bin/
  console               # IRB console with gem loaded
  setup                 # Installation script
```

All Ruby code lives under `lib/brainpipe/`. The main module is `Brainpipe`, defined in `lib/brainpipe.rb`.

## Common Commands

### Setup and Installation
```bash
bin/setup                        # Install dependencies
bundle install                   # Install gems
bundle exec rake install         # Build and install gem locally
bundle exec rake install:local   # Install without pushing to remote
```

### Development
```bash
bin/console                      # Launch IRB with the gem loaded
```

### Building and Releasing
```bash
bundle exec rake build           # Build .gem file into pkg/
bundle exec rake clean           # Remove temporary products
bundle exec rake clobber         # Remove all generated files
bundle exec rake release         # Tag, build, and push to rubygems.org
```

## Development Workflow

- The gem requires Ruby >= 2.7.0
- Version number is defined in `lib/brainpipe/version.rb`
- Gem specification is in `brainpipe.gemspec`
- No test framework is currently configured
- When adding new files, create them under `lib/brainpipe/` and require them in `lib/brainpipe.rb`
