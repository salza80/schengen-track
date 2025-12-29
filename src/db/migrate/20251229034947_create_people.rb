class CreatePeople < ActiveRecord::Migration[7.1]
  def change
    # Create table only if it doesn't exist
    unless table_exists?(:people)
      create_table :people do |t|
        t.references :user, null: false, foreign_key: true, index: true
        t.string :first_name, null: false
        t.string :last_name
        t.references :nationality, foreign_key: { to_table: :countries }, index: true
        t.boolean :is_primary, default: false, null: false

        t.timestamps
      end
    end
    
    # Data migration is handled in MoveVisitsAndVisasToPeople
    # (db/migrate/20251229035005_move_visits_and_visas_to_people.rb)
  end
end
