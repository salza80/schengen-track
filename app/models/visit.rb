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
    Visit.where("person_id = ? and entry_date <= ? and id <> ?", person_id, entry_date, id)
  end
  
  def post_visits
    Visit.where("person_id = ? and entry_date >= ? and id <> ?", person_id, entry_date, id)
  end


  def self.find_by_date(start_date, end_date)
    return nil if start_date.nil? && end_date.nil?
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
    from = entry_date + 1.day if entry_date
    to = exit_date - 1.day if exit_date

    overlap = Visit.find_by_date(from, to)
    return nil unless overlap
    overlap = overlap.select{ |v| v.id != id }
    errors.add(:base, 'the entry and exit dates should not overlap with an existing visit.') if overlap.count > 0

  end

end
