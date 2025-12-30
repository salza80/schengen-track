class CreateVisas < ActiveRecord::Migration[5.1]
  def change
    create_table :visas do |t|
      t.date :start_date
      t.date :end_date
      t.integer :no_entries
      t.text :visa_type
      t.references :user
      # Note: person_id is added later in 20251229035005_move_visits_and_visas_to_people.rb
      t.timestamps null: false
    end
    # Foreign key to people is added in the later migration after people table is recreated
  end
end


