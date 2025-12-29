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
        User.find_each do |user|
          Person.create!(
            user_id: user.id,
            first_name: user.first_name.presence || 'Guest',
            last_name: user.last_name,
            nationality_id: user.nationality_id,
            is_primary: true
          )
        end
      end
    end
  end
end
