class DropPeople < ActiveRecord::Migration[5.1]
  def change
    remove_index :visits, :person_id
    remove_column :visits, :person_id, :integer
    remove_column :visas, :person_id, :integer

    remove_index :people, :nationality_id
    remove_index :people, :user_id
    drop_table :people
  end
end
