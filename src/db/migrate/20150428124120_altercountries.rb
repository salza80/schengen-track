class Altercountries < ActiveRecord::Migration[5.1]
  def change
     rename_column :countries, :EU_memeber_state, :EU_member_state
  end
end
