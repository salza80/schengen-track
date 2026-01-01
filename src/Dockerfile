#!/bin/sh
# Builder stage
FROM public.ecr.aws/docker/library/ruby:3.3.6-slim AS builder
WORKDIR /app

RUN apt-get update -qq && \
    apt-get upgrade -y -qq && \
    apt-get install -y -qq build-essential libpq-dev

RUN bundle config --global frozen 1

COPY Gemfile Gemfile.lock /app/
RUN bundle install

# Final stage
FROM public.ecr.aws/docker/library/ruby:3.3.6-slim
WORKDIR /app

RUN apt-get update -qq && apt-get upgrade -y -qq

RUN apt-get install -y -qq curl bash libpq-dev

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . /app/
ENV RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_ENV="production" \
    BUNDLE_WITHOUT="development"

# Precompile assets
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

