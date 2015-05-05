class Visa < ActiveRecord::Base
  belongs_to :person
  validates :start_date, :end_date, :person, :visa_type, :no_entries, presence: true
  validate :start_date_must_be_less_than_end
  validates :visa_type, inclusion: { in: %w(R S), message: "%{value} is not a valid visa type" }
  default_scope { order('start_date ASC, end_date ASC') }

  def self.find_schengen
    where('visa_type = ?', 'S')
  end

  def self.find_residence
    where('visa_type = ?', 'R')
  end

  def self.find_schengen_visa(entry_date, exit_date)
    return none if entry_date.nil? && exit_date.nil?
    return none if entry_date.nil?
    if exit_date.nil?
      find_schengen.where('(:entry_date >= start_date and :entry_date <= end_date)', entry_date: entry_date).last
    else
      find_schengen.where('(:exit_date >= start_date and :exit_date <= end_date) AND (:entry_date >= start_date and :entry_date <= end_date)', entry_date: entry_date, exit_date: exit_date).last
    end
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
