require 'test_helper'

class VisitAllowanceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:Sally)
    @person = people(:sally_person)
    @person.visits.delete_all
    [['2027-01-01', '2027-01-30'], ['2027-02-10', '2027-03-11']].each do |entry, exit|
      @person.visits.create!(country: countries(:Germany), entry_date: entry, exit_date: exit)
    end
  end

  test 'a final 30 day stay has the same allowance before saving and after reopening in every locale' do
    params = { date: '2027-04-01', exit_date: '2027-04-30', country_code: 'DE' }
    get max_stay_info_visits_path(locale: :en, format: :json), params: params
    assert_response :success
    assert_equal 30, response.parsed_body['max_days']
    assert_equal '2027-04-30', response.parsed_body['exit_date_iso']
    trip = @person.visits.create!(country: countries(:Germany), entry_date: params[:date], exit_date: params[:exit_date])
    I18n.available_locales.each do |locale|
      assert_no_difference('Visit.count') do
        get max_stay_info_visits_path(locale: locale, format: :json), params: params.merge(visit_id: trip.id)
      end
      assert_response :success
      result = response.parsed_body
      assert_equal 30, result['max_days']
      assert_equal '2027-04-30', result['exit_date_iso']
      assert_equal I18n.t('days.tooltip.days_used', count: 61, locale: locale), result.dig('entry_info', 'days_used')
      assert_equal I18n.t('days.tooltip.days_used', count: 90, locale: locale), result.dig('departure_info', 'days_used')
      assert_equal I18n.t('visits.remaining_after_visit', count: 0, locale: locale), result.dig('departure_info', 'remaining')
    end
  end

  test 'changing the draft dates replaces the saved visit and previews a 91st day without saving it' do
    trip = @person.visits.create!(country: countries(:Germany), entry_date: '2027-04-01', exit_date: '2027-04-30')
    params = { date: '2027-04-01', exit_date: '2027-05-01', country_code: 'DE', visit_id: trip.id }
    get max_stay_info_visits_path(locale: :en, format: :json), params: params
    assert_equal 30, response.parsed_body['max_days']
    assert_equal 'Days used: 91/90', response.parsed_body.dig('departure_info', 'days_used')
    assert_equal I18n.t('days.tooltip.overstay', days: 1), response.parsed_body.dig('departure_info', 'overstay')
    get max_stay_info_visits_path(locale: :en, format: :json), params: params.merge(date: '2027-04-02')
    assert_equal 30, response.parsed_body['max_days']
    assert_equal '2027-05-01', response.parsed_body['exit_date_iso']
    assert_equal 'Days used: 90/90', response.parsed_body.dig('departure_info', 'days_used')
    assert_equal Date.new(2027, 4, 30), trip.reload.exit_date
  end

  test 'outside Schengen and incomplete draft dates do not retain a departure summary' do
    params = { date: '2027-04-01', exit_date: '2027-04-30', country_code: 'AU' }
    get max_stay_info_visits_path(locale: :en, format: :json), params: params
    assert_nil response.parsed_body['departure_info']
    get max_stay_info_visits_path(locale: :en, format: :json), params: params.merge(country_code: 'DE', exit_date: '')
    assert_nil response.parsed_body['departure_info']
    ['invalid', (Date.today + 21.years).iso8601, ['2027-04-30']].each do |exit_date|
      get max_stay_info_visits_path(locale: :en, format: :json), params: params.merge(country_code: 'DE', exit_date: exit_date)
      assert_response :success
      assert_nil response.parsed_body['departure_info']
    end
  end

  test 'an overlapping draft cannot break the allowance preview or show invalid departure usage' do
    @person.visits.create!(country: countries(:Australia), entry_date: '2027-05-01', exit_date: '2027-05-02')
    %w[2027-05-04 2028-01-01].each do |exit_date|
      draft = @person.visits.build(country: countries(:Germany), entry_date: '2027-04-01', exit_date: exit_date)
      refute draft.valid?
      assert_no_difference('Visit.count') do
        get max_stay_info_visits_path(locale: :en, format: :json), params: {
          date: draft.entry_date.iso8601, exit_date: draft.exit_date.iso8601, country_code: 'DE'
        }
      end
      assert_response :success
      assert_nil response.parsed_body['departure_info']
      assert_equal 30, response.parsed_body['max_days']
      assert_equal '2027-04-30', response.parsed_body['exit_date_iso']
    end
  end

  test 'a draft entry during a waiting period retains the eligibility warning' do
    sign_in users(:BigVisits)
    get max_stay_info_visits_path(locale: :en, format: :json), params: {
      date: '2016-02-01', exit_date: '2016-02-02', country_code: 'DE'
    }
    assert_equal false, response.parsed_body['show']
    assert_equal I18n.t('days.tooltip.wait', days: 148), response.parsed_body.dig('entry_info', 'wait')
  end

  test 'the next visit permits the shared border date but not an overlapping extra day' do
    @person.visits.delete_all
    trip = @person.visits.create!(country: countries(:Germany), entry_date: '2027-01-01', exit_date: '2027-01-10')
    @person.visits.create!(country: countries(:Australia), entry_date: '2027-01-10', exit_date: '2027-01-20')
    I18n.available_locales.each do |locale|
      get max_stay_info_visits_path(locale: locale, format: :json), params: {
        date: '2027-01-01', exit_date: '2027-01-10', country_code: 'DE', visit_id: trip.id
      }
      assert_response :success
      assert_equal 10, response.parsed_body['max_days']
      assert_equal '2027-01-10', response.parsed_body['exit_date_iso']
      assert_equal 'next_visit', response.parsed_body['constraint_type']
    end
    assert trip.valid?, trip.errors.full_messages.join(', ')
    trip.exit_date += 1.day
    refute trip.valid?
  end

  test 'an earlier Schengen limit is not extended to reach the next visit' do
    @person.visits.create!(country: countries(:Australia), entry_date: '2027-05-01', exit_date: '2027-05-02')
    get max_stay_info_visits_path(locale: :en, format: :json), params: {
      date: '2027-04-01', exit_date: '2027-04-30', country_code: 'DE'
    }
    assert_equal 30, response.parsed_body['max_days']
    assert_equal '2027-04-30', response.parsed_body['exit_date_iso']
    assert_equal 'schengen', response.parsed_body['constraint_type']
  end

  test 'shared Schengen entry attribution is explained in visit rows in every locale' do
    @person.visits.delete_all
    @person.visits.create!(country: countries(:Germany), entry_date: '2028-02-28', exit_date: '2028-03-03')
    outside = @person.visits.create!(country: countries(:Australia), entry_date: '2028-03-03', exit_date: '2028-03-06')
    @person.visits.create!(country: countries(:Germany), entry_date: '2028-03-06', exit_date: '2028-03-07')
    calc = Schengen::Calculator.new(@person)
    assert_equal 5, calc.find_visit(outside.id).schengen_days
    assert_equal 6, calc.calculated_days.find { |day| day.the_date == Date.new(2028, 3, 6) }.schengen_days_count
    assert calc.find_visit(outside.id).schengen_days_exclude_shared_entry
    I18n.available_locales.each do |locale|
      get private_visits_path(locale: locale)
      assert_response :success
      assert_select '.trips-table .shared-entry-note', text: I18n.t('visits.shared_entry_note', locale: locale), count: 1
    end
  end

  test 'free movement is retained for calendar dates with and without recorded visits' do
    @person.update!(nationality: countries(:Germany))
    get private_days_path(locale: :en, year: 2027)
    assert_response :success
    %w[2027-01-01 2027-12-31].each do |date|
      assert_select ".day-cell[data-date='#{date}']" do |cells|
        assert_includes cells.first['data-bs-title'], I18n.t('days.tooltip.no_schengen_limit')
        refute_includes cells.first['data-bs-title'], 'Days used:'
        refute_includes cells.first['data-bs-title'], 'Can stay:'
      end
    end
  end
end
