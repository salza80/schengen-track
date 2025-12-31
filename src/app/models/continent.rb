class Continent < ApplicationRecord
  has_many :countries
  validates :continent_code, :name, presence: true

  def name
    return self[:name] if I18n.locale == :en
    localized_name
  end

  def localized_name(locale = I18n.locale)
    key = "continents.#{continent_key}"
    I18n.t(key, locale: locale, default: self[:name])
  end

  private

  def continent_key
    # Convert "North America" to "north_america"
    self[:name].downcase.gsub(' ', '_')
  end
end
