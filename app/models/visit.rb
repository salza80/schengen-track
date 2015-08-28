class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
  validate :dates_must_not_overlap
  attr_accessor :no_schengen_callback
  after_save :update_visits
  after_update :update_visits
  after_destroy :update_visits
  
  default_scope { order('entry_date ASC, exit_date ASC') }

  # initialise a new visit

  def self.with_default(person)
    # register_oauth_with_matching_email(auth)
    new do |v|
      v.person = person
      v.entry_date = person.visits.last.exit_date unless person.visits.empty?
      v.exit_date  = v.entry_date + 1.day unless v.entry_date.nil?
    end
  end

  # checks if visit is OK
  def visit_check?
    if visa_required?
      return visa_check?
    else
      return schengen_check?
    end
  end

  # Visits calculated fields
  def no_days
    return nil unless exit_date
    (exit_date - entry_date).to_i + 1
  end

  # number of schengen days remaining (never negative)
  def schengen_days_remaining
    return nil unless schengen_days
    return 0 if visa_required? && visa_exists? == false
    return 90 - schengen_days if schengen_days <= 90
    0
  end

  # Is visited country in schengen zone at time of this visit
  def schengen?
    country.schengen?(entry_date)
  end

  # Checks schengen 90 days requirement (and continuious 90 day limit for old schengen calc)
  def schengen_check?
    schengen_overstay? == false && continuious_overstay? == false
  end

  # check if over 90 days
  def schengen_overstay?
    return schengen_days > 90 if schengen_days
    true
  end

  # number of days over the 90 day limit
  def schengen_overstay_days
    return nil unless schengen_days
    days = schengen_days
    days > 90 ? days - 90 : 0
  end

  # check if in zone for 90 days continuius
  def continuious_overstay?
    no_days_continuous_in_schengen > 90
  end

  # Number of days over continuious day stay limit
  def continuous_overstay_days
    days = continuous_overstay_days
    days > 90 ? days - 90 : 0
  end

  #calculate how many days continuious in schengen zone
  def no_days_continuous_in_schengen
    return  nil unless exit_date
    return 0 unless schengen?
    visits = (previous_schengen_visits.sort_by(&:entry_date) << self).reverse!
    cont_days_cnt = 0 
    prev_entry_date = nil
    visits.each do |v|
      if (v.exit_date - 1.day) == prev_entry_date || prev_entry_date.nil?
        cont_days_cnt += v.no_days
      elsif v.exit_date == prev_entry_date
        cont_days_cnt += v.no_days - 1
      else
        return cont_days_cnt
      end
      prev_entry_date = v.entry_date
    end
    cont_days_cnt
  end

  # get all previous visits
  def previous_visits
    person.visits.where('entry_date <= ? and id <> ?', entry_date, id)
  end
  
  # get all post visits
  def post_visits
    person.visits.where('entry_date >= ? and id <> ?', entry_date, id)
  end

  # get all previous visits in the schengen zone only
  def previous_schengen_visits
    previous_visits.select(&:schengen?)
  end

  # get the next visit
  def next_visit
    post_visits.first
  end

  # get previous visits in the last 180 days
  def previous_180_days_visits
    person.visits.find_by_date((entry_date - 180.days), exit_date).select { |v| v.id != id && v.schengen? && v.entry_date <= entry_date}
  end

  # Methods applicable when VISA is required

  #check if a visa is required before entry
  def visa_required?
    person.visa_required? && schengen?
  end

  # check all requirements are satisfied when a visa is required
  def visa_check?
    schengen_overstay? == false && visa_overstay? == false
  end

  # check if visa has been overstayed by date
  def visa_date_overstay?
    return false unless visa_required?
    visa = schengen_visa
    return true unless visa
    exit_date >  visa.end_date
  end
  # check of the visa has been overstayed (either by date or number of entries)
  def visa_overstay?
    visa_date_overstay? || visa_entry_overstay?
  end

  # number of days overstay if has been overstayed by da
  def visa_overstay_days
    if visa_entry_overstay?
      return no_days
    elsif visa_date_overstay?
      return visa_date_overstay_days
    else
      0
    end
  end

  # number of days overstay if visa dates have been overstayed
  def visa_date_overstay_days
    return nil unless exit_date
    return 0 unless visa_date_overstay?
    visa = schengen_visa
    return no_days unless visa
    exit_date <= visa.end_date ? 0 : exit_date - visa.end_date
  end

  # check if a visa exists for this visit
  def visa_exists?
    schengen_visa.nil? == false
  end

  # check if visa has been overstayed by number of entry limit
  def visa_entry_overstay?
    return false unless person.visa_required? && schengen?
    return true unless visa_exists?
    visa = schengen_visa
    visa.no_entries != 0 && visa_entry_count > visa.no_entries
  end

  # number of visits on current visa
  def visa_entry_count
    p = previous_visits_on_current_visa << self
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

  # get number of entries allowed on current visa
  def visa_entries_allowed
    visa = schengen_visa
    return nil unless visa
    visa.no_entries
  end

  # get the schengen visa for this visit
  def schengen_visa
    return nil unless person.visa_required?
    visa = Visa.find_schengen_visa(entry_date, exit_date)
    visa = Visa.find_schengen_visa(entry_date, nil) unless visa
    visa
  end
  
  #get all previous visits on the current visa
  def previous_visits_on_current_visa
    return previous_visits unless person.visa_required?
    return Visit.none unless visa_exists?
    visa = schengen_visa
    previous_visits.select { |v| v.schengen_visa == visa }
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
    return false unless person
    vis = person.visits.find_by_date(entry_date, exit_date)
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

  def update_visits
    return if no_schengen_callback
    calc = SchengenCalculator.new(person, self)
    calc.calculate_schengen
  end
end
