class CreateIndex < ActiveRecord::Migration[5.1]
  def change
    # Note: Foreign key for visits -> people is added in a later migration
    # after the people table is created (20251229034947_create_people.rb)
    # This migration originally tried to add it but people table didn't exist yet
  end
end

