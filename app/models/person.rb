class Person < ActiveRecord::Base
  belongs_to :nationality, class_name: 'Country'
  has_many :visits
  validates :first_name, :last_name, :nationality, presence: true


  def full_name
    (first_name + ' ' + last_name).strip
  end
end
