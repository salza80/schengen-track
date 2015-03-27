class Person < ActiveRecord::Base
  belongs_to :nationality, class_name: 'Country'
  has_many :visits
end
