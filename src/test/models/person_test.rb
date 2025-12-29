require 'test_helper'

class PersonTest < ActiveSupport::TestCase
  test 'should belong to user and nationality' do
    person = people(:sally_person)
    assert_not_nil person.user
    assert_not_nil person.nationality
  end

  test 'should have many visits' do
    person = people(:sally_person)
    assert person.visits.count > 0
  end

  test 'should have many visas' do
    person = people(:visa_required_person)
    assert person.visas.count > 0
  end

  test 'should require first_name' do
    person = Person.new(user: users(:Sally), nationality: countries(:Australia))
    assert person.invalid?
    assert person.errors[:first_name].any?
  end

  test 'should not require last_name' do
    person = Person.new(
      user: users(:Sally),
      first_name: 'Test',
      nationality: countries(:Australia)
    )
    assert person.valid?
  end

  test 'full_name should combine first and last name' do
    person = people(:sally_person)
    assert_equal 'Sally Mclean', person.full_name
  end

  test 'full_name should return only first name if last name is blank' do
    person = Person.new(first_name: 'John')
    assert_equal 'John', person.full_name
  end

  test 'nationality_with_default should return nationality name' do
    person = people(:sally_person)
    assert_equal 'Australia', person.nationality.name
  end

  test 'nationality_with_default should return default country if no nationality' do
    person = Person.new(first_name: 'Test')
    default_country = person.nationality_with_default
    assert_not_nil default_country
    assert_equal 'US', default_country.country_code
  end

  test 'visa_required? should return false for visa-free countries' do
    person = people(:sally_person)
    assert_not person.visa_required?
  end

  test 'visa_required? should return true for visa-required countries' do
    person = people(:visa_required_person)
    assert person.visa_required?
  end

  test 'visa_required? should return false for default country (US) if nationality not set' do
    person = Person.new(first_name: 'Test')
    # US has visa_required: 'A' (visa waiver)
    assert_not person.visa_required?
  end

  test 'should order by is_primary desc then full_name' do
    user = users(:Sally)
    people_ordered = user.people.ordered
    assert_equal people(:sally_person), people_ordered.first
  end

  test 'should not allow deleting last person' do
    person = people(:sally_person)
    # Delete the alternative person first
    people(:sally_person_alt).destroy
    
    # Now try to delete the last person (who is also primary)
    assert_not person.destroy
    assert person.errors[:base].any?
    assert_match /Cannot delete the primary person/, person.errors[:base].first
  end

  test 'should allow deleting person if not the last one' do
    person = people(:sally_person_alt)
    assert person.destroy
  end

  test 'destroying person should delete associated visits' do
    person = people(:test1_person)
    visit_count = person.visits.count
    assert visit_count > 0
    
    # Create another person for the same user and make them primary
    new_person = Person.create!(
      user: person.user,
      first_name: 'Another',
      nationality: countries(:Australia),
      is_primary: false
    )
    
    # Make the new person primary so we can delete test1_person
    person.update!(is_primary: false)
    new_person.update!(is_primary: true)
    
    person.destroy
    assert_equal 0, Visit.where(person_id: person.id).count
  end

  test 'destroying person should delete associated visas' do
    person = people(:visa_required_person)
    visa_count = person.visas.count
    assert visa_count > 0
    
    # Create another person for the same user and make them primary
    new_person = Person.create!(
      user: person.user,
      first_name: 'Another',
      nationality: countries(:Australia),
      is_primary: false
    )
    
    # Make the new person primary so we can delete visa_required_person
    person.update!(is_primary: false)
    new_person.update!(is_primary: true)
    
    person.destroy
    assert_equal 0, Visa.where(person_id: person.id).count
  end
end
