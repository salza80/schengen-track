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
    
    # Note: Data migration moved to separate rake task (db:migrate_people_data)
    # This allows for batched processing and better timeout handling
  end
end
