class Country < ApplicationRecord
  has_many :users
  has_many :visits
  belongs_to :continent
  validates :country_code, :name, :continent, :visa_required, presence: true
  validates_inclusion_of :EU_member_state,
                         :additional_visa_waiver,
                         in: [true, false]

  def self.with_booking_affiliate
    where('affiliate_booking_html > ""')
  end

  def self.find_by_nationality(nationality)
    where('replace(lower(nationality),\' \', \'_\') = :n OR replace(lower(nationality),\' \', \'_\') = :ns OR replace(lower(name),\' \', \'_\') = :nc',
          n: nationality.downcase,
          ns: nationality.downcase.singularize,
          nc: nationality.downcase)
  end

  def self.outside_schengen
    where('visa_required <> :free', free: 'F')
  end

  def self.order_by_name
    order(:name)
  end

  def name
    return self[:name] if I18n.locale == :en
    localized_name
  end

  def localized_name(locale = I18n.locale)
    key = "#{country_code}_name"
    translated_value_for(key, locale) || translated_value_for(key, I18n.default_locale) || self[:name]
  end

  def nationality_translated
    return self[:nationality] if I18n.locale == :en

    key = "#{country_code}_nationality"
    translated_value_for(key, I18n.locale) || translated_value_for(key, I18n.default_locale) || self[:nationality]
  end

  def nationality_english
    return nationality
  end

  def nationality_plural
    key = "#{country_code}_nationality_plural"
    translated_value_for(key, I18n.locale) || translated_value_for(key, I18n.default_locale) || name
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

  private

  def translated_value_for(key, locale)
    return I18n.t(key, locale: locale) if I18n.exists?(key, locale)
    nil
  end
end
