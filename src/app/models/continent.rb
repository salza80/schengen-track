class Continent
  include Dynamoid::Document
  has_many :countries
  field :name, :string
  field :continent_code, :string
  validates :continent_code, :name, presence: true
end