class CreatePeople < ActiveRecord::Migration[7.1]
  def change
    create_table :people do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :first_name, null: false
      t.string :last_name
      t.references :nationality, foreign_key: { to_table: :countries }, index: true
      t.boolean :is_primary, default: false, null: false

      t.timestamps
    end

    # Data migration: Create one Person per existing User
    reversible do |dir|
      dir.up do
        User.reset_column_information
        
        # Use bulk insert for better performance
        people_data = User.pluck(:id, :first_name, :last_name, :nationality_id, :created_at, :updated_at).map do |user_id, first_name, last_name, nationality_id, created_at, updated_at|
          {
            user_id: user_id,
            first_name: first_name.presence || 'Guest',
            last_name: last_name,
            nationality_id: nationality_id,
            is_primary: true,
            created_at: created_at || Time.current,
            updated_at: updated_at || Time.current
          }
        end
        
        # Insert all people at once (much faster than individual creates)
        Person.insert_all(people_data) if people_data.any?
      end
    end
  end
end
