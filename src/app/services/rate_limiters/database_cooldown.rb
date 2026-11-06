require 'digest'
require 'pg'

module RateLimiters
  class DatabaseCooldown
    def self.claim(scope:, identifier:, period:)
      now = Time.current
      key = Digest::SHA256.hexdigest([name, scope, identifier].join(':'))
      result = ActiveRecord::Base.connection.raw_connection.exec_params(<<~SQL.squish, [key, scope, identifier, now, now + period])
        INSERT INTO api_rate_limits
          (rate_limit_key, scope, identifier, window_start, expires_at, count, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, 1, $4, $4)
        ON CONFLICT (rate_limit_key) DO UPDATE SET
          window_start = EXCLUDED.window_start,
          expires_at = EXCLUDED.expires_at,
          count = 1,
          updated_at = EXCLUDED.updated_at
        WHERE api_rate_limits.expires_at <= EXCLUDED.window_start
        RETURNING count
      SQL
      result.ntuples.positive?
    rescue ActiveRecord::ActiveRecordError, PG::Error => error
      Rails.logger.error("Recovery cooldown store unavailable (#{error.class})")
      raise DatabaseFixedWindow::Unavailable, 'Rate-limit store unavailable'
    end
  end
end
