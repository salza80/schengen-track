class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true

  def no_days
    return nil if self.exit_date.nil?
    (exit_date - entry_date).to_i + 1
  end
end
