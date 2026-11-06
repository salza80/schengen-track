require 'test_helper'

class CalculatorReadOnlyTest < ActionDispatch::IntegrationTest
  setup do
    post user_session_path(locale: :en), params: { user: { email: users(:Sally).email, password: 'password' } }
    assert_redirected_to visits_path(locale: :en)
    @person = people(:sally_person)
    @old = legacy_visit(Date.today - 21.years)
    @future = legacy_visit(Date.today + 21.years)
    @active = @person.visits.create!(country: countries(:Germany), entry_date: Date.today + 5.days,
                                     exit_date: Date.today + 10.days)
  end

  test 'guest calculator navigation also preserves out-of-range records' do
    delete destroy_user_session_path(locale: :en)
    source = User.create!(guest: true, email: "read_guest_#{SecureRandom.hex(8)}@example.com", password: 'password123',
                          first_name: 'Guest', last_name: 'Traveler', nationality: countries(:USA))
    guest = import_guest_calculation(source)
    @person = guest.people.find_by!(is_primary: true)
    legacy_visit(Date.today - 21.years)
    legacy_visit(Date.today + 21.years)
    before = Visit.order(:id).map(&:attributes)

    [visits_path(locale: :en), days_path(locale: :en)].each do |path|
      get path, headers: { 'Sec-Fetch-Site' => 'cross-site' }
      assert_response :success
      assert_equal guest.id, session[:guest_user_id]
      assert_equal before, Visit.order(:id).map(&:attributes)
    end
  end

  test 'cross-site GET and HEAD calculator navigation preserves all stored visits' do
    before = Visit.order(:id).map(&:attributes)
    [[:get, visits_path(locale: :en)], [:get, days_path(locale: :en)],
     [:head, visits_path(locale: :en)], [:head, days_path(locale: :en)]].each do |method, path|
      public_send method, path, headers: { 'Sec-Fetch-Site' => 'cross-site', 'Referer' => 'https://external.example/' }
      assert_response :success
      assert_equal before, Visit.order(:id).map(&:attributes)
    end

    get visits_path(locale: :en)
    assert_select "a.edit-visit-link[data-visit-id='#{@active.id}']", count: 1
    assert_select "a.edit-visit-link[data-visit-id='#{@old.id}']", count: 0
    assert_select "a.edit-visit-link[data-visit-id='#{@future.id}']", count: 0
  end

  test 'CSV export uses the supported display window without purging excluded records' do
    before = Visit.order(:id).map(&:attributes)
    get visits_path(locale: :en, format: :csv)
    assert_response :success
    assert_includes response.body, @active.entry_date.iso8601
    assert_not_includes response.body, @old.entry_date.iso8601
    assert_not_includes response.body, @future.entry_date.iso8601
    assert_equal before, Visit.order(:id).map(&:attributes)
  end

  test 'calendar record lookup keeps its inclusive supported range without modifying history' do
    past_boundary = legacy_visit(Date.today - 20.years)
    future_boundary = legacy_visit(Date.today + 20.years - 5.days)
    [[@old, false], [@future, false], [@active, true], [past_boundary, true], [future_boundary, true]].each do |visit, visible|
      get for_date_visits_path(locale: :en, format: :json), params: { date: visit.entry_date.iso8601 }
      assert_response :success
      assert_equal visible, response.parsed_body.any? { |row| row['id'] == visit.id }
      assert Visit.exists?(visit.id)
    end
  end

  test 'retained history counts consistently toward visa entries without expanding the day window' do
    @person.visits.delete_all
    @person.update!(nationality: countries(:India))
    old = legacy_visit(Date.today - 21.years)
    countries(:Germany).update!(schengen_start_date: old.entry_date - 1.year)
    active = @person.visits.create!(country: countries(:Germany), entry_date: Date.today + 5.days,
                                    exit_date: Date.today + 10.days)
    @person.visas.create!(visa_type: 'S', no_entries: 0, start_date: old.entry_date - 1.day,
                         end_date: active.exit_date + 30.days)
    calc = Schengen::Days::Calculator.new(@person, visits: @person.visits.where(id: active.id))
    assert_equal 2, active.visa_entry_count
    assert_equal active.visa_entry_count, calc.find_by_date(active.entry_date).visa_entry_count
    assert_nil calc.find_by_date(old.entry_date)

    get visits_path(locale: :en, format: :csv)
    assert_response :success
    assert_includes response.body, '2 of Multi'
    assert_not_includes response.body, old.entry_date.iso8601
    assert Visit.exists?(old.id)
  end

  private

  def legacy_visit(entry_date)
    @person.visits.new(country: countries(:Germany), entry_date: entry_date, exit_date: entry_date + 5.days).tap do |visit|
      # Represent dates that were valid on creation but have aged out, or
      # legacy records predating the current validation rules.
      visit.save!(validate: false)
    end
  end
end
