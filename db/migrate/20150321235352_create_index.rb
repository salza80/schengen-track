class CreateIndex < ActiveRecord::Migration
  def change
    add_index :visits, :person_id
    add_foreign_key :visits, :people
  end
end

