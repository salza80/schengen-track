#!/bin/bash
set -e

# Your test steps here
cd src

# Check if docker-compose.yml exists
if [ -f "docker-compose.yml" ]; then
  docker-compose -f "docker-compose.yml" up -d
fi

# Run the tests
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec bundle exec rake
