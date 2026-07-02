require 'digest'

module RateLimiters
  class DatabaseFixedWindow
    CLEANUP_SAMPLE_RATE = 0.01

    Result = Struct.new(:allowed?, :limit, :remaining, :reset_at, :count, keyword_init: true)

    def initialize(scope:, identifier:, limit:, period:)
      @scope = scope
      @identifier = identifier.presence || 'unknown'
      @limit = limit
      @period = period
    end

    def call
      delete_expired_limits if cleanup_sampled?

      count = increment_window_count
      Result.new(
        allowed?: count <= limit,
        limit: limit,
        remaining: [limit - count, 0].max,
        reset_at: window_end,
        count: count
      )
    rescue StandardError => e
      raise unless missing_rate_limit_table_error?(e)

      Rails.logger.warn("API rate limiter skipped because api_rate_limits table is unavailable: #{e.class}: #{e.message}")
      Result.new(
        allowed?: true,
        limit: limit,
        remaining: limit,
        reset_at: window_end,
        count: 0
      )
    end

    private

    attr_reader :scope, :identifier, :limit, :period

    def increment_window_count
      result = ActiveRecord::Base.connection.raw_connection.exec_params(<<~SQL.squish, insert_values)
        INSERT INTO api_rate_limits
          (rate_limit_key, scope, identifier, window_start, expires_at, count, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, 1, $6, $6)
        ON CONFLICT (rate_limit_key)
        DO UPDATE SET
          count = api_rate_limits.count + 1,
          updated_at = EXCLUDED.updated_at
        RETURNING count
      SQL

      result.first.fetch('count').to_i
    end

    def insert_values
      now = Time.current
      [
        rate_limit_key,
        scope,
        identifier,
        window_start,
        window_end,
        now
      ]
    end

    def delete_expired_limits
      ApiRateLimit.delete_expired!
    end

    def cleanup_sampled?
      rand < CLEANUP_SAMPLE_RATE
    end

    def rate_limit_key
      Digest::SHA256.hexdigest([scope, identifier, window_start.to_i].join(':'))
    end

    def window_start
      @window_start ||= Time.zone.at((Time.current.to_i / period.to_i) * period.to_i)
    end

    def window_end
      @window_end ||= window_start + period
    end

    def missing_rate_limit_table_error?(error)
      ([error, error.cause].compact).any? { |cause| cause.class.name == 'PG::UndefinedTable' } ||
        (error.message.match?(/api_rate_limits/i) && error.message.match?(/does not exist|no such table/i))
    end
  end
end
