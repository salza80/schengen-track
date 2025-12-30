class AddPeopleFieldsToUser < ActiveRecord::Migration[5.1]
  def change
    # add new columns to user and visas and visits to remove people table
    add_column :users, :first_name, :string unless column_exists?(:users, :first_name)
    add_column :users, :last_name, :string unless column_exists?(:users, :last_name)
    add_column :users, :nationality_id, :integer unless column_exists?(:users, :nationality_id)
    add_index :users, :nationality_id unless index_exists?(:users, :nationality_id)

    add_column :visits, :user_id, :integer unless column_exists?(:visits, :user_id)
    add_column :visas, :user_id, :integer unless column_exists?(:visas, :user_id)

    add_foreign_key :visas, :users unless foreign_key_exists?(:visas, :users)
    add_foreign_key :visits, :users unless foreign_key_exists?(:visits, :users)

  end
end

