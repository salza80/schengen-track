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
      # Use full calculator (same as visits page)
      calc = Schengen::Days::Calculator.new(current_user_or_guest_user)
      @days = calc.calculated_days
      @overstay = calc.schengen_overstay?
      @next_entry_days = calc.next_entry_days
      
      @view_mode = params[:view] || 'calendar'
      
      if @view_mode == 'calendar'
        setup_calendar_view_infinite
        calculate_status_summary if @days.any?
      end
    end
  end

  private
  
  def setup_calendar_view_infinite
    # Calculate year range (works with or without visits)
    if @days.any?
      first_date = @days.min_by(&:the_date).the_date
      last_date = @days.max_by(&:the_date).the_date
      start_year = first_date.year - 1
      end_year = [last_date.year + 2, Date.today.year + 2].max
    else
      # No visits: show current year ± 2 years
      start_year = Date.today.year - 2
      end_year = Date.today.year + 2
    end
    
    @available_years = (start_year..end_year).to_a
    @selected_year = (params[:year] || Date.today.year).to_i
    
    # Clamp selected year to available range
    @selected_year = @selected_year.clamp(start_year, end_year)
    
    # Set prev/next years (always available now)
    @prev_year = @selected_year - 1 if @selected_year > start_year
    @next_year = @selected_year + 1 if @selected_year < end_year
    
    # Filter days for this year
    year_days = @days.select { |d| d.the_date.year == @selected_year }
    
    # Calculate year summary
    @year_summary = calculate_year_summary(year_days, @selected_year)
    
    # Format months
    @calendar_months = format_calendar_data(year_days, @selected_year)
  end
  
  def calculate_year_summary(year_days, year)
    visits_in_year = current_user_or_guest_user.visits.where(
      '(entry_date >= ? AND entry_date <= ?) OR (exit_date >= ? AND exit_date <= ?) OR (entry_date <= ? AND exit_date >= ?)',
      Date.new(year, 1, 1), Date.new(year, 12, 31),
      Date.new(year, 1, 1), Date.new(year, 12, 31),
      Date.new(year, 1, 1), Date.new(year, 12, 31)
    ).count
    
    # Count schengen days in this year
    schengen_days = year_days.count { |d| d.schengen? }
    
    # Get max schengen count in this year
    max_count = year_days.map(&:schengen_days_count).compact.max || 0
    
    {
      visits_count: visits_in_year,
      schengen_days: schengen_days,
      max_schengen_count: max_count
    }
  end
  
  def calculate_status_summary
    return unless @days.any?
    
    # Find today's day data, or the latest day if today is not in the range
    today = Date.today
    today_day = @days.find { |d| d.the_date == today }
    reference_day = today_day || @days.max_by(&:the_date)
    
    @status_summary = {
      current_days: reference_day.schengen_days_count || 0,
      max_days: 90,
      remaining_days: [90 - (reference_day.schengen_days_count || 0), 0].max,
      status: if reference_day.overstay?
                'overstay'
              elsif (reference_day.schengen_days_count || 0) >= 80
                'warning'
              else
                'safe'
              end,
      last_calculated_date: reference_day.the_date
    }
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
      
      # If no visit data exists for this date, create an empty SchengenDay object
      # so the cell is still clickable for adding new visits
      if day_data.nil?
        day_data = Schengen::Days::SchengenDay.new(date)
      end
      
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
