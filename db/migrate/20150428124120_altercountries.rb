class Altercountries < ActiveRecord::Migration
  def change
     rename_column :countries, :EU_memeber_state, :EU_member_state
  end
end
