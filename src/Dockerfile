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

ENV NODE_VERSION v20.18.1

# Install Node.js directly
RUN curl -o- https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y -qq nodejs

RUN npm install -g npm@10.2.5

RUN npm i -g yarn

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . /app/
ENV RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_ENV="production" \
    BUNDLE_WITHOUT="development"

# Install JavaScript dependencies
RUN yarn install --frozen-lockfile --production

# Touch JavaScript files and clear asset cache to force fingerprint regeneration
RUN find app/assets/javascripts -type f -exec touch {} \; && \
    rm -rf public/assets/* tmp/cache/assets

RUN NODE_OPTIONS=--openssl-legacy-provider SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

