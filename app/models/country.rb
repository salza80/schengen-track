class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  validates :country_code, :name, presence: true


  def is_schengen (use_date = Time.now)
    return false if self.schengen_start_date.nil?
    self.schengen_start_date <= use_date

  end
end
