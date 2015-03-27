class Country < ActiveRecord::Base
  has_many :people
  has_many :visits
end
