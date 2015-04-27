class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, presence: true

  def schengen?(use_date = Time.now)
    return false if schengen_start_date.nil?
    schengen_start_date <= use_date
  end
end
