.ONESHELL:
SHELL = /bin/sh

.PHONY: all test

test:
	# Install dependencies
	apk add yaml gcc g++ make linux-headers
	gem update --system
	gem update bundler
	# Install gems
	bundle install
	# Set needed Env for tests
	export REDIS_URL=redis://localhost:6379/2
	# Run tests
	bundle exec rake
