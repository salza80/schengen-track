class CreateIndex < ActiveRecord::Migration[5.1]
  def change
    add_foreign_key :visits, :people
  end
end

