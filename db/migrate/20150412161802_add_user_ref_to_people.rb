class AddUserRefToPeople < ActiveRecord::Migration
  def change
    add_reference :people, :user, index: true
    add_foreign_key :people, :users
  end
end
