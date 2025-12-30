class MoveVisitsAndVisasToPeople < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_person_reference(:visits)
    add_person_reference(:visas)

    backfill_people(:visits)
    backfill_people(:visas)

    finalize_schema(:visits)
    finalize_schema(:visas)
  end

  def down
    restore_user_reference(:visits)
    restore_user_reference(:visas)

    remove_reference_if_exists(:visits, :person)
    remove_reference_if_exists(:visas, :person)
  end

  private

  def add_person_reference(table_name)
    return if column_exists?(table_name, :person_id)

    add_reference table_name, :person, foreign_key: true, index: true
  end

  def backfill_people(table_name)
    return unless column_exists?(table_name, :person_id)
    return unless column_exists?(table_name, :user_id)

    say_with_time("Backfilling #{table_name}.person_id") do
      execute <<~SQL.squish
        UPDATE #{table_name}
           SET person_id = primary_people.id
          FROM people AS primary_people
         WHERE primary_people.user_id = #{table_name}.user_id
           AND primary_people.is_primary = TRUE
           AND #{table_name}.person_id IS NULL;
      SQL
    end
  end

  def finalize_schema(table_name)
    return unless column_exists?(table_name, :person_id)

    change_column_null table_name, :person_id, false

    if foreign_key_exists?(table_name, :users)
      remove_foreign_key table_name, :users
    end

    remove_column table_name, :user_id if column_exists?(table_name, :user_id)
  end

  def restore_user_reference(table_name)
    add_reference table_name, :user, foreign_key: true, index: true unless column_exists?(table_name, :user_id)
    change_column_null table_name, :person_id, true if column_exists?(table_name, :person_id)
  end

  def remove_reference_if_exists(table_name, column_name)
    return unless column_exists?(table_name, "#{column_name}_id")

    remove_reference table_name, column_name, foreign_key: true
  end
end
