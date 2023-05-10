class AddUserRefToPeople < ActiveRecord::Migration[5.1]
  def change
    add_reference :people, :user, index: true
    add_foreign_key :people, :users
  end
end
