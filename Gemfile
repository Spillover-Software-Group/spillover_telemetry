# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The suite runs the collectors against the real runtimes rather than against stand-ins, and boots a
# dummy application the way a container does. None of these is a dependency of the gem: a collector
# asks whether its runtime is loaded and reports nothing where it is not.
group :development, :test do
  # The Rails series both applications run. The gem supports 7.1 and up, and this is what its suite
  # proves it on.
  gem "rails", "~> 7.1.0"
  # Active Support 7.1's JSON encoder passes an option json 3 no longer takes, and both applications
  # are on json 2. This is the stack the suite proves the gem on.
  gem "json", "~> 2.7"

  gem "minitest"
  gem "puma"
  gem "rackup"
  gem "rubocop-rails-omakase", require: false
  gem "solid_queue"
  gem "sqlite3"
end
