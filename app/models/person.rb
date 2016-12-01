class Person < ActiveRecord::Base
  belongs_to :nationality, class_name: 'Country'
  belongs_to :user
  has_many :visits, dependent: :destroy
  has_many :visas, dependent: :destroy
  validates :first_name, :last_name, :nationality, presence: true
  def full_name
    [first_name, last_name].join(' ').strip
  end

  # used on normal registration to cope guest visits
  def copy_from(person)
    person.visits.each do |p|
      visits << p.dup
    end
  end


  #used on omniauth signup
  def self.copy_from(person)
    p = Person.new
    p.first_name = person.first_name || "New"
    p.last_name = person.last_name || "User"
    person.visits.each do |v|
      p.visits << v.dup
    end
    p.nationality = person.nationality
    p
  end

  def nationality
    super || Country.find_by(country_code: "US")
  end

  def visa_required?
    nationality.visa_required == 'V'
  end
end
