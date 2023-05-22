class Addguesttouser < ActiveRecord::Migration[5.1]
  def change
    add_column :users, :guest, :boolean, null: false, default: false
  end
end
