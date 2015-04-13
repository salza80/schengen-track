class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  validate :entry_date_must_be_less_than_exit
 
  def entry_date_must_be_less_than_exit
    if exit_date.present? && entry_date > exit_date
      errors.add(:entry_date, 'should be earlier than the exit date')
    end
  end


  def no_days
    return nil if exit_date.nil?
    (exit_date - entry_date).to_i + 1
  end

  def previous_visits
    Visit.where("person_id = ? and entry_date <= ? and id <> ?", person_id, entry_date, id)
  end
  
  def post_visits
    Visit.where("person_id = ? and entry_date >= ? and id <> ?", person_id, entry_date, id)
  end
end
