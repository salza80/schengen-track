class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, :continent, :visa_required,
            :nationality,  presence: true
  validates_inclusion_of :EU_member_state,
                         :additional_visa_waiver,
                         :old_schengen_calc,
                         in: [true, false]

  def self.with_booking_affiliate
    where('affiliate_booking_html > ""')
  end

  def self.find_by_nationality(nationality)
    where('lower(nationality) = :n', n: nationality.downcase)
  end

  def self.outside_schengen
    where('visa_required <> "F"')
  end

  def nationality_plural
    ending = nationality.last(3)

    if ending == 'ese' || ending == 'ese' || ending == 'nch' || ending == 'iss'
      nationality
    else
      nationality.pluralize
    end
  end

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
