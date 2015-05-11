class Person < ActiveRecord::Base
  belongs_to :nationality, class_name: 'Country'
  belongs_to :user
  has_many :visits, dependent: :destroy
  has_many :visas, dependent: :destroy
  validates :first_name, :last_name, :nationality, presence: true
  after_save :update_visits
  after_update :update_visits
  def full_name
    [first_name, last_name].join(' ').strip
  end

  def copy_from(person)
    person.visits.each do |p|
      visits << p.dup
    end
  end

  def visa_required?
    nationality.visa_required == 'V'
  end
 

  private

  def update_visits
    calc = SchengenCalculator.new(self)
    calc.calculate_schengen
  end
end
