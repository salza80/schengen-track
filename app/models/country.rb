class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, :continent, :EU_member_state, :visa_required, :old_schengen_calc, :additional_visa_waiver, presence: true

  def schengen?(use_date = Time.now)
    return false if schengen_start_date.nil?
    schengen_start_date <= use_date
  end
end
