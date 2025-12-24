require 'test_helper'

class DaysHelperTest < ActionView::TestCase
  include DaysHelper
  
  # ====================
  # A. Day Cell Class Tests
  # ====================
  
  test "day_cell_class returns outside-schengen for non-schengen days" do
    day = OpenStruct.new(
      schengen?: false,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'outside-schengen', day_cell_class(day)
  end
  
  test "day_cell_class returns in-schengen-safe for safe days" do
    day = OpenStruct.new(
      schengen?: true,
      schengen_days_count: 45,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'in-schengen-safe', day_cell_class(day)
  end
  
  test "day_cell_class returns in-schengen-warning for days over 80" do
    day = OpenStruct.new(
      schengen?: true,
      schengen_days_count: 85,
      danger?: false,
      warning?: false
    )
    
    assert_equal 'in-schengen-warning', day_cell_class(day)
  end
  
  test "day_cell_class returns overstay for danger days" do
    day = OpenStruct.new(
      schengen?: true,
      schengen_days_count: 95,
      danger?: true,
      warning?: false
    )
    
    assert_equal 'overstay', day_cell_class(day)
  end
  
  test "day_cell_class returns waiting-period for warning days" do
    day = OpenStruct.new(
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
      hasCountry?: true,
      country_name: 'France',
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
      country_name: 'Germany',
      stayed_country: country,
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
    assert_equal 'badge-success', status_badge_class('safe')
    assert_equal 'badge-warning', status_badge_class('warning')
    assert_equal 'badge-danger', status_badge_class('overstay')
    assert_equal 'badge-info', status_badge_class('unknown')
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
end
