class Visa < ApplicationRecord
  belongs_to :user
  validates :start_date, :end_date, :user, :visa_type, :no_entries, presence: true
  validates :visa_type, inclusion: { in: %w(R S), message: "%{value} is not a valid visa type" }
  validate :start_date_must_be_less_than_end
  validate :dates_must_not_overlap
  default_scope { order('start_date ASC, end_date ASC') }
  scope :schengen, -> { where(visa_type: 'S') }
  scope :residence, -> { where(visa_type: 'R') }


  def self.find_visa_by_date(vstart_date, vend_date)
    return Visa.none if vstart_date.nil? && vend_date.nil?
    return Visa.none if vstart_date.nil?
    if vend_date.nil?
      where('(:start_date >= start_date and :start_date <= end_date)', start_date: vstart_date)
    else
      where(' (:start_date >= start_date and :start_date <= end_date) OR (:end_date >= start_date and :end_date <= end_date) OR (:start_date < start_date AND :end_date > end_date)', start_date: vstart_date, end_date: vend_date)
    end
  end

  def self.find_schengen_visa(vstart_date, vend_date)
    schengen.find_visa_by_date(vstart_date, vend_date).where('(:start_date >= start_date and :start_date <= end_date)', start_date: vstart_date).last
    
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
  
  def date_overlap?
    return false unless user
    vis = user.visas.find_visa_by_date(start_date, end_date)
    vis = vis.select { |v| v.visa_type == visa_type && v.id != id && v.end_date != start_date && v.start_date != end_date }
    vis.count > 0
  end

  private

  # Custom Validation Methods

  def dates_must_not_overlap
    return unless date_overlap?
    errors.add(:base, 'the start and end dates should not overlap with an existing visas.')
  end

  def start_date_must_be_less_than_end
    return if end_date.nil? || start_date.nil?
    errors.add(:start_date, 'should be earlier than the end date') if end_date < start_date
  end
end

