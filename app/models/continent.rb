class Continent < ApplicationRecord
  has_many :countries
  validates :continent_code, :name, presence: true


end
