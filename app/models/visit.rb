class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
  validate :dates_must_not_overlap
  attr_accessor :no_schengen_callback
  after_save VisitCallbacks
  after_update VisitCallbacks
  after_destroy VisitCallbacks
  # before_save :schengen_days_update
  # before_create :schengen_days_update
  
  default_scope { order('entry_date ASC, exit_date ASC') }

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

  def visa_overstay?
    visa_overstay_days > 0
  end

  def visa_entry_overstay?
    return false unless visa_required?
    return false unless schengen?
    visa = schengen_visa
    return true unless visa
    return false if visa.no_entries == 0
    visa_entry_count > visa.no_entries
  end

  def visa_exists?
    return true if schengen_visa
  end

  def visa_entries_allowed
    return 0 unless visa_required?
    visa = schengen_visa
    return nil unless visa
    visa.no_entries
  end

  def schengen_overstay_days
    return nil unless schengen_days
    if schengen_days > 90
      schengen_days - 90
    else
      0
    end
  end

  def visa_required?
    return nil unless person
    return person.nationality.visa_required == "V"
  end

  def schengen_visa
    return nil unless visa_required?
    visa = Visa.find_schengen_visa(entry_date, exit_date)
    if visa.nil?
      visa = Visa.find_schengen_visa(entry_date, nil)
    end
    visa
  end

  def visa_entry_count
    if visa_required?
      visa = schengen_visa
      return nil unless visa
      p = previous_schengen_visits.select { |v| v if v.entry_date >= visa.start_date && v.entry_date <= visa.end_date }
    else
      p = previous_schengen_visits
    end
    num = 0
    num = p.count if p
    num += 1 if schengen?
    num
  end

  def visa_overstay_days
    return 0 unless visa_required?
    return 0 unless schengen?
    visa = schengen_visa
    return no_days unless visa
    return 0 if exit_date.nil?
    cnt = visa_entry_count
    if visa.no_entries == 0 || visa.no_entries >= cnt
      return 0 if exit_date <= visa.end_date
      exit_date - visa.end_date
    else
      return no_days
    end
  end


  def previous_visits
    person.visits.where('entry_date <= ? and id <> ?', entry_date, id)
  end
  
  def post_visits
    person.visits.where('entry_date >= ? and id <> ?', entry_date, id)
  end

  def previous_schengen_visits
    previous_visits.select { |v|  v.schengen? }
  end

  def next_visit
    post_visits.first
  end

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

  # def schengen_days_update
  #   self.schengen_days = calc_schengen_day_count
  # end

  def previous_180_days_visits
    return Visit.none unless exit_date
    person.visits.find_by_date((exit_date - 180.days), exit_date).select { |v| v.id != id }
  end

  def date_overlap?(visit)
    return false if visit.id == id
    return false if visit.entry_date.nil? || entry_date.nil?
    return false if visit.exit_date.nil? && exit_date.nil?
    return visit.entry_date < exit_date unless visit.exit_date
    return false if visit.exit_date < visit.entry_date
    return visit.exit_date > entry_date unless exit_date
    overlap = visit.entry_date >  entry_date && visit.entry_date < exit_date
    return true if overlap
    overlap = visit.exit_date > entry_date && visit.exit_date < exit_date
    return true if overlap
    visit.entry_date < entry_date && visit.exit_date > exit_date
  end



  private

  # Custom Validation Methods

  def entry_date_must_be_less_than_exit
    return unless exit_date.present? && entry_date > exit_date
    errors.add(:entry_date, 'should be earlier than the exit date')
  end

  def dates_must_not_overlap
    return unless person
    return unless entry_date
    person.visits.each do |v|
      if date_overlap?(v)
        errors.add(:base, 'the entry and exit dates should not overlap with an existing visit.')
        return
      end
    end
  end
end
