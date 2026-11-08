require 'test_helper'
require 'ostruct'

class DaysHelperTest < ActionView::TestCase
  include DaysHelper

  test 'freedom of movement tooltips explain the exemption without a false allowance' do
    person = Person.new(nationality: countries(:Germany))
    trip = Visit.new(country: countries(:Germany), entry_date: '2027-01-01', exit_date: '2027-04-01')
    day = Schengen::Days::Calculator.new(person, visits: [trip]).find_by_date(Date.new(2027, 4, 1))
    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        tooltip = day_tooltip(day)
        assert_includes tooltip, I18n.t('days.tooltip.no_schengen_limit')
        refute_includes tooltip, I18n.t('days.tooltip.days_used', count: 0)
        refute_includes tooltip, I18n.l(Date.new(2027, 6, 30), format: :long)
      end
    end
  end

  test 'a tooltip extends an occupied day through its actual last permitted date' do
    day = OpenStruct.new(the_date: Date.new(2027, 4, 29), schengen?: true, hasCountry?: false,
                         schengen_days_count: 89, max_remaining_days: 1, overstay_days: 0, remaining_wait: nil)
    assert_includes day_tooltip(day), 'April 30, 2027'
    day.max_remaining_days = 0
    refute_includes day_tooltip(day), 'Can stay:'
  end

  test 'country labels localize same-day trips and country changes without changing country names' do
    day = OpenStruct.new
    germany = OpenStruct.new(name: 'Allemagne')
    australia = OpenStruct.new(name: 'Australie')
    I18n.with_locale(:fr) do
      day.entered_country = germany
      day.exited_country = australia
      assert_equal 'Entrée : Allemagne · Sortie : Australie', day_country_name(day)
      day.exited_country = germany
      assert_equal 'Entrée et sortie : Allemagne', day_country_name(day)
      day.entered_country = nil
      assert_equal 'Allemagne', day_country_name(day)
      day.exited_country = nil
      assert_equal 'Hors Schengen', day_country_name(day)
      day.stayed_country = germany
      assert_equal 'Allemagne', day_country_name(day)
    end
  end
  
  # ====================
  # A. Day Cell Class Tests
  # ====================
  
  test "day_cell_class returns outside-schengen for recorded non-schengen days" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: false,
      hasCountry?: true,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'outside-schengen', day_cell_class(day)
  end

  test "day_cell_class returns no-travel when no country is recorded" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: false,
      hasCountry?: false,
      danger?: false,
      warning?: false
    )

    assert_equal 'no-travel', day_cell_class(day)
  end
  
  test "day_cell_class returns in-schengen-safe for safe days" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: true,
      schengen_days_count: 45,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'in-schengen-safe', day_cell_class(day)
  end
  
  test "day_cell_class remains in-schengen-safe for days over 80" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: true,
      schengen_days_count: 85,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'in-schengen-safe', day_cell_class(day)
  end
  
  test "day_cell_class returns overstay for danger days" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: true,
      schengen_days_count: 95,
      danger?: true,
      warning?: false
    )
    
    assert_equal 'overstay', day_cell_class(day)
  end
  
  test "day_cell_class returns waiting-period for warning days" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: false,
      danger?: false,
      warning?: true
    )
    
    assert_equal 'waiting-period', day_cell_class(day)
  end
  
  # ====================
  # B. Tooltip Generation Tests
  # ====================
  
  test "day_tooltip includes country name" do
    country = OpenStruct.new(name: 'France')
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: country,
      schengen_days_count: nil,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, '<strong>France</strong>'
  end
  
  test "day_tooltip includes days used" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: false,
      schengen_days_count: 45,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Days used: 45/90'
  end
  
  test "day_tooltip includes overstay warning" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: false,
      schengen_days_count: nil,
      max_remaining_days: nil,
      overstay_days: 5,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'OVERSTAY: +5 days'
    assert_includes tooltip, 'text-danger'
  end
  
  test "day_tooltip combines multiple parts with br tags" do
    country = OpenStruct.new(name: 'Germany')
    day = OpenStruct.new(
      hasCountry?: true,
      stayed_country: country,
      the_date: Date.new(2024, 1, 1),
      schengen_days_count: 60,
      max_remaining_days: 30,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, '<br>'
    assert_includes tooltip, 'Germany'
    assert_includes tooltip, 'Days used: 60/90'
    assert_includes tooltip, 'Can stay: 30 more days'
  end
  
  # ====================
  # C. Status Helper Tests
  # ====================
  
  test "status_icon_class returns correct icons for all statuses" do
    assert_includes status_icon_class('safe'), 'fa-check-circle'
    assert_includes status_icon_class('safe'), 'text-success'
    
    assert_includes status_icon_class('warning'), 'fa-exclamation-triangle'
    assert_includes status_icon_class('warning'), 'text-warning'
    
    assert_includes status_icon_class('overstay'), 'fa-times-circle'
    assert_includes status_icon_class('overstay'), 'text-danger'
    
    assert_includes status_icon_class('unknown'), 'fa-info-circle'
    assert_includes status_icon_class('unknown'), 'text-info'
  end
  
  test "status_text_class returns correct bootstrap colors" do
    assert_equal 'success', status_text_class('safe')
    assert_equal 'warning', status_text_class('warning')
    assert_equal 'danger', status_text_class('overstay')
    assert_equal 'info', status_text_class('unknown')
  end
  
  test "status_badge_class returns correct badge styles" do
    assert_equal 'text-bg-success', status_badge_class('safe')
    assert_equal 'text-bg-warning', status_badge_class('warning')
    assert_equal 'text-bg-danger', status_badge_class('overstay')
    assert_equal 'text-bg-info', status_badge_class('unknown')
  end
  
  # ====================
  # D. Date Helper Tests
  # ====================
  
  test "is_today? correctly identifies today's date" do
    today_day = OpenStruct.new(the_date: Date.today)
    yesterday_day = OpenStruct.new(the_date: Date.yesterday)
    
    assert is_today?(today_day)
    assert_not is_today?(yesterday_day)
  end
  
  test "is_today? handles nil safely" do
    # The method returns nil for nil input, but we want it to be falsey
    result = is_today?(nil)
    assert_not result, "is_today?(nil) should be falsey"
  end
  
  # ====================
  # E. Visa Display Tests
  # ====================
  
  test "day_cell_class returns overstay for visa violation" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: true,
      schengen_days_count: 45,
      danger?: false,
      warning?: false,
      visa_warning?: true
    )
    
    assert_equal 'overstay', day_cell_class(day)
  end
  
  test "day_cell_class prioritizes visa warning over safe" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      schengen?: true,
      schengen_days_count: 30,
      danger?: false,
      warning?: false,
      visa_warning?: true
    )
    
    assert_equal 'overstay', day_cell_class(day)
  end
  
  test "day_tooltip includes visa valid status" do
    visa = OpenStruct.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31))
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'France'),
      user_requires_visa?: true,
      schengen?: true,
      visa: visa,
      visa_valid?: true,
      has_limited_entries?: false,
      schengen_days_count: 30,
      max_remaining_days: 60,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Valid visa'
    assert_includes tooltip, 'text-success'
  end
  
  test "day_tooltip shows no visa warning" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'Germany'),
      user_requires_visa?: true,
      schengen?: true,
      visa: nil,
      visa_valid?: false,
      schengen_days_count: 30,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'NO VISA'
    assert_includes tooltip, 'text-danger'
  end
  
  test "day_tooltip shows visa entries when limited" do
    visa = OpenStruct.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31))
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'Italy'),
      user_requires_visa?: true,
      schengen?: true,
      visa: visa,
      visa_valid?: true,
      visa_entry_valid?: true,
      has_limited_entries?: true,
      visa_entry_count: 2,
      visa_entries_allowed: 4,
      schengen_days_count: 45,
      max_remaining_days: 45,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Entries: 2/4'
  end
  
  test "day_tooltip shows entry limit exceeded" do
    visa = OpenStruct.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31))
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'Spain'),
      user_requires_visa?: true,
      schengen?: true,
      visa: visa,
      visa_valid?: true,
      visa_entry_valid?: false,
      has_limited_entries?: true,
      visa_entry_count: 3,
      visa_entries_allowed: 2,
      schengen_days_count: 50,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Entry limit exceeded: 3/2'
    assert_includes tooltip, 'text-danger'
  end
  
  test "day_tooltip shows both visa and schengen overstay" do
    visa = OpenStruct.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31))
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'France'),
      user_requires_visa?: true,
      schengen?: true,
      visa: visa,
      visa_valid?: true,
      visa_entry_valid?: false,
      has_limited_entries?: true,
      visa_entry_count: 3,
      visa_entries_allowed: 2,
      schengen_days_count: 95,
      max_remaining_days: nil,
      overstay_days: 5,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Entry limit exceeded'
    assert_includes tooltip, 'SCHENGEN OVERSTAY: +5 days'
  end
  
  test "day_tooltip shows outside visa period" do
    visa = OpenStruct.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 6, 30))
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'Germany'),
      user_requires_visa?: true,
      schengen?: true,
      visa: visa,
      visa_valid?: false,  # Outside period
      schengen_days_count: 20,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_includes tooltip, 'Outside visa period'
    assert_includes tooltip, 'text-danger'
  end
  
  test "day_tooltip does not show visa info for non-schengen days" do
    day = OpenStruct.new(
      the_date: Date.new(2024, 1, 1),
      hasCountry?: true,
      stayed_country: OpenStruct.new(name: 'Australia'),
      user_requires_visa?: true,
      schengen?: false,  # Non-Schengen
      visa: nil,
      schengen_days_count: nil,
      max_remaining_days: nil,
      overstay_days: 0,
      remaining_wait: nil
    )
    
    tooltip = day_tooltip(day)
    assert_not_includes tooltip, 'visa'
    assert_not_includes tooltip, 'NO VISA'
  end
end
