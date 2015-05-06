class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, :continent, :visa_required,  presence: true
  validates_inclusion_of :EU_member_state,  :additional_visa_waiver , :old_schengen_calc, in: [true, false]

  def schengen?(use_date = Time.now)
    return false if schengen_start_date.nil?
    schengen_start_date <= use_date
  end
end
