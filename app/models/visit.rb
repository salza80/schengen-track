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
  # before_save :schengen_days_update
  # before_create :schengen_days_update
  
  default_scope { order('entry_date ASC, exit_date ASC') }


# Visits Methods
  def no_days
    return nil unless exit_date
    (exit_date - entry_date).to_i + 1
  end

  def schengen_days_remaining
    return nil unless schengen_days
    return 90 - schengen_days if schengen_days <= 90
    0
  end

  def schengen?
    country.schengen?(entry_date)
  end

  def schengen_overstay?
    schengen_days > 90 if schengen_days
  end

  def schengen_overstay_days
    return nil unless schengen_days
    if schengen_days > 90
      schengen_days - 90
    else
      0
    end
  end

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

  def previous_visits
    person.visits.where('entry_date <= ? and id <> ?', entry_date, id)
  end
  
  def post_visits
    person.visits.where('entry_date >= ? and id <> ?', entry_date, id)
  end

  def previous_schengen_visits
    previous_visits.select(&:schengen?)
  end

  def next_visit
    post_visits.first
  end

  def previous_180_days_visits
    return Visit.none unless exit_date
    person.visits.find_by_date((exit_date - 180.days), exit_date).select { |v| v != self }
  end

  #Methods applicable when VISA is required


  def visa_required?
    person.visa_required? && schengen?
  end

  def visa_overstay?
    visa_overstay_days > 0
  end

  def visa_exists?
    return true if schengen_visa
  end

  def visa_entry_overstay?
    return false unless person.visa_required? && schengen?
    return true unless visa_exists?
    visa = schengen_visa
    visa.no_entries != 0 && visa_entry_count > visa.no_entries
  end

  def visa_entry_count
    p = previous_visits_on_current_visa
    return nil unless p
    cnt = p.count
    cnt += 1 if schengen?
    cnt
  end

  def schengen_visa
    return nil unless person.visa_required?
    visa = Visa.find_schengen_visa(entry_date, exit_date)
    visa = Visa.find_schengen_visa(entry_date, nil) unless visa
    visa
  end
  

  def previous_visits_on_current_visa
    return previous_schengen_visits unless person.visa_required?
    return Visit.none unless visa_exists?
    visa = schengen_visa
    previous_schengen_visits.select { |v| v.schengen_visa == visa }
  end


  def visa_overstay_days
    return 0 unless visa_required?
    return nil unless exit_date
    return no_days if visa_entry_overstay?
    visa = schengen_visa
    exit_date <= visa.end_date ? 0 : exit_date - visa.end_date
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
