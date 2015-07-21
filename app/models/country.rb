class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, :continent, :visa_required,  presence: true
  validates_inclusion_of :EU_member_state,
                         :additional_visa_waiver,
                         :old_schengen_calc,
                         in: [true, false]

  def schengen?(use_date = Time.now)
    return false if schengen_start_date.nil?
    schengen_start_date <= use_date
  end

  def visa_required_desc
    case  visa_required
    when 'F'
      return 'Freedom of Movement'
    when 'A'
      return 'Automatic Schengen Visa'
    when 'V'
      return 'Visa Required'
    else
      return nil
    end
  end
end
