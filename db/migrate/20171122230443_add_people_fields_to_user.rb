class AddPeopleFieldsToUser < ActiveRecord::Migration
  def change
    # add new columns to user and visas and visits to remove people table
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :nationality_id, :integer
    add_index :users, :nationality_id

    add_column :visits, :user_id, :integer
    add_column :visas, :user_id, :integer

    add_foreign_key :visas, :users
    add_foreign_key :visits, :users

    # update data in new columns

    execute "UPDATE users set first_name =  people.first_name, last_name=people.last_name, nationality_id=people.nationality_id FROM people where users.id = people.user_id;"

    execute "UPDATE visits set user_id =  people.user_id FROM people where visits.person_id = people.id;"
    execute "UPDATE visas set user_id =  people.user_id FROM people where visas.person_id = people.id;"

  end
end

