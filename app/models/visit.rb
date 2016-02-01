class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
  validate :dates_must_not_overlap
  
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
    person.visits.find_by_date((entry_date - 180.days), exit_date).select { |v| v.id != self.id && v.schengen? && v.entry_date <= entry_date }
  end

  # Methods applicable when VISA is required

  #check if a visa is required before entry
  def visa_required?
    person.visa_required? && schengen?
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
    return nil unless person.visa_required?
    visa = person.visas.find_schengen_visa(entry_date, exit_date)
    visa = person.visas.find_schengen_visa(entry_date, nil) unless visa
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
