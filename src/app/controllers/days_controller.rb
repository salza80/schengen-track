class DaysController < ApplicationController
  before_action :set_visit, only: [:show, :edit, :update, :destroy]
  before_action :set_country_continent, only: [:new, :edit, :update, :create]
  #before_action :authenticate_user!

  # GET /visits
  # GET /visits.json
  def index
    if current_user_or_guest_user.visa_required? 
      redirect_to visits_path
    else
      days_calc = Schengen::Days::Calculator.new(current_user_or_guest_user)
      @days = days_calc.calculated_days
      @overstay = days_calc.schengen_overstay?
      
      @view_mode = params[:view] || 'calendar'
      
      if @view_mode == 'calendar' && @days.any?
        setup_calendar_view
      end
    end
  end

  private
  
  def setup_calendar_view
    # Determine date range
    range = calculate_month_range(@days)
    @available_years = range[:available_years]
    
    # Get selected year (default to most recent)
    @selected_year = params[:year]&.to_i || @available_years.last
    
    # Ensure selected year is valid
    unless @available_years.include?(@selected_year)
      @selected_year = @available_years.last
    end
    
    # Filter days for this year only
    year_days = @days.select { |d| d.the_date.year == @selected_year }
    
    # Format into calendar structure
    @calendar_months = format_calendar_data(year_days, @selected_year)
    
    # Determine prev/next years
    current_index = @available_years.index(@selected_year)
    @prev_year = current_index&.positive? ? @available_years[current_index - 1] : nil
    @next_year = current_index && current_index < @available_years.length - 1 ? @available_years[current_index + 1] : nil
  end
  
  def calculate_month_range(days)
    return { available_years: [] } if days.empty?
    
    first_date = days.first.the_date.beginning_of_month
    
    # Find last day where count > 0
    last_day_with_count = days.reverse.find { |d| d.schengen_days_count && d.schengen_days_count.positive? }
    last_date = last_day_with_count ? last_day_with_count.the_date.end_of_month : days.last.the_date.end_of_month
    
    years = (first_date.year..last_date.year).to_a
    
    { available_years: years, start_date: first_date, end_date: last_date }
  end
  
  def format_calendar_data(year_days, year)
    months = []
    
    # Generate all 12 months for the year
    (1..12).each do |month_num|
      month_start = Date.new(year, month_num, 1)
      month_end = month_start.end_of_month
      
      # Get days for this month
      month_days = year_days.select { |d| d.the_date.month == month_num }
      
      # Build week structure
      weeks = build_weeks(month_start, month_end, month_days)
      
      months << {
        month: month_num,
        year: year,
        month_name: month_start.strftime('%B %Y'),
        weeks: weeks
      }
    end
    
    months
  end
  
  def build_weeks(month_start, month_end, month_days)
    weeks = []
    current_week = []
    
    # Pad start of month (empty cells before 1st)
    start_wday = month_start.wday # 0 = Sunday
    current_week = Array.new(start_wday, nil)
    
    # Fill in days
    month_start.upto(month_end) do |date|
      day_data = month_days.find { |d| d.the_date == date }
      current_week << day_data
      
      # Complete week (7 days)
      if current_week.length == 7
        weeks << current_week
        current_week = []
      end
    end
    
    # Pad end of last week
    if current_week.any?
      current_week += Array.new(7 - current_week.length, nil)
      weeks << current_week
    end
    
    weeks
  end
  
end
