class ApiRateLimit < ApplicationRecord
  def self.delete_expired!(now = Time.current)
    where('expires_at < ?', now).delete_all
  end
end
