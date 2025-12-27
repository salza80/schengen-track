class Visit < ApplicationRecord
  belongs_to :country
  belongs_to :user
  validates :country, :user, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
  validate :dates_must_not_overlap
  validate :dates_must_be_within_reasonable_range
  
  default_scope { order('entry_date ASC, exit_date ASC') }

  # initialise a new visit

  def self.with_default(user)
    # register_oauth_with_matching_email(auth)
    new do |v|
      v.user = user
      v.entry_date = user.visits.last.exit_date unless user.visits.empty?
      v.exit_date  = v.entry_date + 1.day unless v.entry_date.nil?
    end
  end

  # Visits calculated fields
  def no_days
    return nil unless exit_date
    (exit_date - entry_date).to_i + 1
  end

  # Is visited country in schengen zone at time of this visit
  def schengen?
    country.schengen?(entry_date)
  end

  # get all previous visits
  def previous_visits
    user.visits.where('entry_date <= ? and id <> ?', entry_date, id)
  end
  
  # get all previous visits in the schengen zone only
  def previous_schengen_visits
    previous_visits.select(&:schengen?)
  end

  # get previous visits in the last 180 days
  def previous_180_days_visits
    user.visits.find_by_date((entry_date - 180.days), exit_date).select { |v| v.id != self.id && v.schengen? && v.entry_date <= entry_date }
  end

  # Methods applicable when VISA is required

  #check if a visa is required before entry
  def visa_required?
    user.visa_required? && schengen?
  end

 
  # check if a visa exists for this visit
  def visa_exists?
    schengen_visa.nil? == false
  end

  # get number of entries allowed on current visa
  def visa_entries_allowed
    visa = schengen_visa
    return nil unless visa
    visa.no_entries
  end

  # get the schengen visa for this visit
  def schengen_visa
    return nil unless user.visa_required?
    visa = user.visas.find_schengen_visa(entry_date, exit_date)
    visa = user.visas.find_schengen_visa(entry_date, nil) unless visa
    visa
  end
  
  #get all previous visits on the current visa
  def previous_visits_on_current_visa
    return previous_visits unless user.visa_required?
    return Visit.none unless visa_exists?
    visa = schengen_visa
    previous_visits.select { |v| v.schengen_visa == visa }
  end

 # number of days overstay if visa dates have been overstayed
  def visa_date_overstay_days
    return nil unless exit_date
    return 0 unless visa_date_overstay?
    visa = schengen_visa
    return no_days unless visa
    exit_date <= visa.end_date ? 0 : exit_date - visa.end_date
  end
  # check if visa has been overstayed by number of entry limit
  def visa_entry_overstay?
    return false unless user.visa_required? && schengen?
    return true unless visa_exists?
    visa = schengen_visa
    visa.no_entries != 0 && visa_entry_count > visa.no_entries
  end

  # number of visits on current visa
  def visa_entry_count
    p = previous_visits_on_current_visa.to_a << self
    return nil unless p
    cnt = 0
    prev_visit = nil
    p.each do |v|
      if v.schengen?
        if prev_visit.nil? == false && prev_visit.schengen?
          cnt += 1 if v.entry_date - prev_visit.exit_date > 1
        else
          cnt += 1
        end
      end
      prev_visit = v
    end
    cnt
  end

 # Scopes

  def self.find_by_date(start_date, end_date)
    return none if start_date.nil? && end_date.nil?
    if start_date.nil?
      where('entry_date <= ?', end_date)
    elsif end_date.nil?
      where('(entry_date >= :start_date or exit_date >= :start_date) or exit_date is null', start_date: start_date)
    else
      return none if end_date < start_date
      r = where('(entry_date >= :start_date and entry_date <= :end_date)', start_date: start_date, end_date: end_date)
      r += where('(exit_date >= :start_date and exit_date <= :end_date)', start_date: start_date, end_date: end_date )
      r += where('(entry_date <= :start_date) and (exit_date >= :end_date OR exit_date is null)', start_date: start_date, end_date: end_date)
      r.uniq(&:id)
    end
  end

  def date_overlap?
    return false unless user
    vis = user.visits.find_by_date(entry_date, exit_date)
    vis = vis.select { |v|  v != self && v.exit_date != entry_date && v.entry_date != exit_date }
    vis.count > 0
  end

  private

  
  # Custom Validation Methods

  def entry_date_must_be_less_than_exit
    return unless exit_date.present? && entry_date > exit_date
    errors.add(:entry_date, 'should be earlier than the exit date')
  end

  def dates_must_not_overlap
    return unless date_overlap?
    errors.add(:base, 'the entry and exit dates should not overlap with an existing travel dates.')
  end

  def dates_must_be_within_reasonable_range
    cutoff_past = Date.today - 20.years
    cutoff_future = Date.today + 20.years

    if entry_date.present? && (entry_date < cutoff_past || entry_date > cutoff_future)
      errors.add(:entry_date, 'must be within 20 years of today')
    end

    if exit_date.present? && (exit_date < cutoff_past || exit_date > cutoff_future)
      errors.add(:exit_date, 'must be within 20 years of today')
    end
  end
end
