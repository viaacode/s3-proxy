.ONESHELL:
SHELL = /bin/bash

.PHONY: all test

test:
	# Install dependacies
	apk add yaml gcc g++ make linux-headers
	# Install gems
	bundle install
	# Set needed Env for tests
	export REDIS_URL=redis://localhost:6379/2
	# Run tests
	bundle exec rake