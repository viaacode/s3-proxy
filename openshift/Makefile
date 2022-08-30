.ONESHELL:
SHELL = /bin/sh

.PHONY: all test

test:
	# Install dependencies
	apk add yaml gcc g++ make linux-headers
	# Install gems
	export BUNDLER_VERSION='2.1.4'
	gem update --system && gem install bundler
	bundle update --bundler && bundle install
	# Set needed Env for tests
	export REDIS_URL=redis://localhost:6379/2
	# Run tests
	bundle exec rake
