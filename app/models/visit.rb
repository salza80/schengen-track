class Visit < ActiveRecord::Base
  belongs_to :country
  belongs_to :person
  validates :country, :person, :entry_date, presence: true
  attr_accessor :running_total_days



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
