class Person < ActiveRecord::Base
  belongs_to :nationality, class_name: 'Country'
  belongs_to :user
  has_many :visits, dependent: :destroy
  validates :first_name, :last_name, :nationality, presence: true

  def full_name
    (first_name + ' ' + last_name).strip
  end

  def copy_from(person)
    person.visits.each do |p|
      visits << p.dup
    end
  end

  def find_visits_by_date(start_date, end_date)
    Visit.find_by_date(self, start_date, end_date)
  end
 
end
