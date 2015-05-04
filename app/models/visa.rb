class Visa < ActiveRecord::Base
  belongs_to :person
  validates :start_date, :end_date, :person, :visa_type, :no_entries, presence: true
  validate :start_date_must_be_less_than_end
  validates :visa_type, inclusion: { in: %w(R S), message: "%{value} is not a valid visa type" }


  def self.find_schengen
    where('visa_type = ?', 'S')
  end

  def self.find_residence
    where('visa_type = ?', 'R')
  end

  def visa_desc
    case  visa_type
    when 'R'
      return 'Resident Visa/Permit'
    when 'S'
      return 'Schengen Visa'
    else
      return nil
    end
  end


  private

  # Custom Validation Methods

  def start_date_must_be_less_than_end
    return if end_date.nil? || start_date.nil?
    errors.add(:start_date, 'should be earlier than the end date') if end_date < start_date
  end
end
