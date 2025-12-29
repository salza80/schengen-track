class MoveVisitsAndVisasToPeople < ActiveRecord::Migration[7.1]
  def change
    # Add person_id to visits and visas
    add_reference :visits, :person, foreign_key: true, index: true
    add_reference :visas, :person, foreign_key: true, index: true

    # Data migration: Map visits and visas to users' primary person
    reversible do |dir|
      dir.up do
        Visit.reset_column_information
        Visa.reset_column_information
        Person.reset_column_information
        
        # Move all visits from user to their primary person
        User.find_each do |user|
          primary_person = user.people.find_by(is_primary: true)
          next unless primary_person
          
          Visit.where(user_id: user.id).update_all(person_id: primary_person.id)
          Visa.where(user_id: user.id).update_all(person_id: primary_person.id)
        end
      end
    end

    # Make person_id required and remove user_id
    change_column_null :visits, :person_id, false
    change_column_null :visas, :person_id, false
    
    remove_foreign_key :visits, :users
    remove_foreign_key :visas, :users
    remove_column :visits, :user_id, :integer
    remove_column :visas, :user_id, :integer
  end
end
