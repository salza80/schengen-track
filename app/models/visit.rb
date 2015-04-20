class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
  validate :dates_must_not_overlap
 




  def no_days
    return nil unless exit_date
    (exit_date - entry_date).to_i + 1
  end

  def previous_visits
    person.visits.where("entry_date <= ? and id <> ?", entry_date, id)
  end
  
  def post_visits
    person.visits.where("entry_date >= ? and id <> ?", entry_date, id)
  end

  def previous_180_days_visits
    return Visit.none unless exit_date
    r=person.visits.find_by_date((exit_date - 180.days), exit_date).select{ |v| v.id != id }
    puts r.inspect
    person.visits.find_by_date((exit_date - 180.days), exit_date).select{ |v| v.id != id }
  end

  def self.find_by_date(start_date, end_date)
    return none if start_date.nil? && end_date.nil?
    if start_date.nil?
      where("entry_date <= ?", end_date)
    elsif end_date.nil?
      where("(entry_date >= ? or exit_date >= :start_date) or exit_date is null", start_date: start_date)
    else
      r = where("(entry_date >= :start_date and entry_date <= :end_date)", { start_date: start_date, end_date: end_date })
      r += where("(exit_date >= :start_date and exit_date <= :end_date)", { start_date: start_date, end_date: end_date })
      r += where("(entry_date <= :start_date) and (exit_date >= :end_date OR exit_date is null)", { start_date: start_date, end_date: end_date })
      r.uniq(&:id)
    end
  end

  private

  # Custom Validation Methods

  def entry_date_must_be_less_than_exit
    if exit_date.present? && entry_date > exit_date
      errors.add(:entry_date, 'should be earlier than the exit date')
    end
  end

  def dates_must_not_overlap
    return unless person
    from = entry_date + 1.day if entry_date
    to = exit_date - 1.day if exit_date

    overlap = person.visits.find_by_date(from, to)
    return nil unless overlap
    overlap = overlap.select{ |v| v.id != id }
    errors.add(:base, 'the entry and exit dates should not overlap with an existing visit.') if overlap.count > 0

  end

end
