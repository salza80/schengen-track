class VisitsController < ApplicationController
  include VisitCleanup
  
  before_action :set_visit, only: [:show, :edit, :update, :destroy]
  before_action :set_country_continent, only: [:new, :edit, :update, :create]
  #before_action :authenticate_user!
  
  # Skip CSRF verification for .js GET requests (new, edit, for_date, max_stay_info)
  # These are safe read-only operations that need to work with AJAX
  skip_before_action :verify_authenticity_token, only: [:new, :edit, :for_date, :max_stay_info], if: -> { request.format.js? || request.format.json? }

  # GET /visits
  # GET /visits.json
  def index
    puts Rails.application.secrets.facebook_id
    
    # Clean up old visits (beyond ±20 years)
    cleanup_old_visits

    calc = Schengen::Calculator.new(current_user_or_guest_user)
    @visits = calc.visits
    if current_user_or_guest_user.visa_required?
      @visas = current_user_or_guest_user.visas.all
    end
    @next_entry_days = calc.next_entry_days
    setup_sidebar_data(calc)
    @show_sidebar_legend = false
    
    # Set SEO meta tags for visits page
    set_visits_meta_tags
    
    respond_to do |format|
      format.html do
        @visits.each do |visit|
          if visit.country && !visit.country.affiliate_booking_html.nil?
            @advertise_country = visit.country
          end
        end
      end
      format.csv { send_data calc.to_csv}
    end
  end
  # GET /visits/1
  # GET /visits/1.json
  def show
  end

  # GET /visits/new
  def new
    @visit = Visit.with_default(current_user_or_guest_user)
    
    # Support pre-filling dates from calendar clicks
    if params[:entry_date]
      @visit.entry_date = Date.parse(params[:entry_date])
      @visit.exit_date = params[:exit_date] ? Date.parse(params[:exit_date]) : @visit.entry_date + 1.day
    end
    
    respond_to do |format|
      format.html # Full page render
      format.js   # AJAX request from calendar
    end
  end

  # GET /visits/1/edit
  def edit
    @continent_default_id = @visit.country.continent.id.to_s
    if @visit.country && !@visit.country.affiliate_booking_html.nil?
      @advertise_country = @visit.country
    end
    
    respond_to do |format|
      format.html # Full page render
      format.js   # AJAX request from calendar
    end
  end

  # POST /visits
  # POST /visits.json
  def create
    @visit = current_user_or_guest_user.visits.build(visit_params) 
    respond_to do |format|
      if @visit.save
        format.html { redirect_to visits_path, notice: 'Visit was successfully created.' }
        format.json { render :show, status: :created, location: @visit }
        format.js   # AJAX request from calendar
      else
        @continent_default_id = @visit&.country&.continent&.id&.to_s || @continent_default_id
        format.html { render :new }
        format.json { render json: @visit.errors, status: :unprocessable_entity }
        format.js   # AJAX request from calendar - show errors
      end
    end
  end

  # PATCH/PUT /visits/1
  # PATCH/PUT /visits/1.json
  def update
    respond_to do |format|
      if @visit.update(visit_params)
        format.html { redirect_to visits_path, notice: 'Visit was successfully updated.' }
        format.json { render :show, status: :ok, location: @visit }
        format.js   # AJAX request from calendar
      else
        format.html { render :edit }
        format.json { render json: @visit.errors, status: :unprocessable_entity }
        format.js   # AJAX request from calendar - show errors
      end
    end
  end

  # DELETE /visits/1
  # DELETE /visits/1.json
  def destroy
    # Store entry date before destroying for calendar redirect
    entry_year = @visit.entry_date.year
    entry_month = @visit.entry_date.month
    
    @visit.destroy
    
    respond_to do |format|
      format.html { 
        # If came from calendar view, redirect back to calendar
        if request.referer&.include?('/days')
          redirect_to days_path(locale: I18n.locale, year: entry_year, month: entry_month), 
                      notice: 'Visit was successfully deleted.'
        else
          # Otherwise redirect to visits list
          redirect_to visits_path(locale: I18n.locale), notice: 'Visit was successfully deleted.'
        end
      }
      format.json { head :no_content }
    end
  end

  # GET /visits/for_date?date=YYYY-MM-DD
  # Returns all visits that include the specified date (for calendar context menu)
  def for_date
    date = Date.parse(params[:date])
    visits = current_user_or_guest_user.visits.find_by_date(date, date)
    
    respond_to do |format|
      format.json { 
        render json: visits.map { |v| {
          id: v.id,
          entry_date: v.entry_date,
          exit_date: v.exit_date,
          country_name: v.country.name,
          country_id: v.country_id,
          schengen: v.schengen?
        }}
      }
    end
  end
  
  # GET /visits/max_stay_info?date=YYYY-MM-DD&country_id=X
  # Returns max stay information for a given entry date and country
  def max_stay_info
    date = Date.parse(params[:date])
    country = Country.find(params[:country_id])
    
    # Check if there's a next visit after this date
    next_visits = current_user_or_guest_user.visits
      .where('entry_date > ?', date)
      .order(:entry_date)
    
    # Exclude the current visit being edited if visit_id is provided
    if params[:visit_id].present?
      next_visits = next_visits.where.not(id: params[:visit_id])
    end
    
    next_visit = next_visits.first
    next_visit_constraint_date = next_visit ? next_visit.entry_date - 1.day : nil
    
    # Check if this is a Schengen country and user requires visa counting
    is_schengen = country.schengen?(date)
    requires_counting = current_user_or_guest_user.nationality.visa_required != 'F'
    
    if is_schengen && requires_counting
      # Calculate Schengen days limit
      calc = Schengen::Days::Calculator.new(current_user_or_guest_user)
      day_info = calc.find_by_date(date)
      
      if day_info && day_info.max_remaining_days && day_info.max_remaining_days > 0
        schengen_exit_date = date + day_info.max_remaining_days.days

        # Compare Schengen limit with next visit constraint
        if next_visit_constraint_date && schengen_exit_date >= next_visit.entry_date
          # Next visit comes before Schengen limit
          days_until_next = (next_visit.entry_date - date).to_i
          render json: {
            show: true,
            max_days: days_until_next,
            exit_date: next_visit_constraint_date.strftime('%b %d, %Y'),
            constrained: true,
            constraint_type: 'next_visit',
            next_entry_date: next_visit.entry_date.strftime('%b %d, %Y')
          }
        else
          # Schengen limit is the constraint (or no next visit)
          render json: {
            show: true,
            max_days: day_info.max_remaining_days,
            exit_date: schengen_exit_date.strftime('%b %d, %Y'),
            constrained: true,
            constraint_type: 'schengen'
          }
        end
      else
        # No Schengen days available, but might have next visit constraint
        if next_visit_constraint_date
          days_until_next = (next_visit.entry_date - date).to_i
          render json: {
            show: true,
            max_days: days_until_next,
            exit_date: next_visit_constraint_date.strftime('%b %d, %Y'),
            constrained: true,
            constraint_type: 'next_visit',
            next_entry_date: next_visit.entry_date.strftime('%b %d, %Y')
          }
        else
          render json: { show: false }
        end
      end
    elsif next_visit_constraint_date
      # Non-Schengen country but has next visit constraint
      days_until_next = (next_visit.entry_date - date).to_i
      render json: {
        show: true,
        max_days: days_until_next,
        exit_date: next_visit_constraint_date.strftime('%b %d, %Y'),
        constrained: true,
        constraint_type: 'next_visit',
        next_entry_date: next_visit.entry_date.strftime('%b %d, %Y')
      }
    else
      render json: { show: false }
    end
  end

  private
    def setup_sidebar_data(calc)
      @days = calc.calculated_days
      @overstay = calc.schengen_overstay?
      calculate_status_summary_for_visits
    end

    def calculate_status_summary_for_visits
      return unless @days&.any?

      today = Date.today
      today_day = @days.find { |d| d.the_date == today } || @days.max_by(&:the_date)

      @status_summary = {
        current_days: today_day.schengen_days_count || 0,
        max_days: 90,
        remaining_days: [90 - (today_day.schengen_days_count || 0), 0].max,
        status: if today_day.overstay?
                  'overstay'
                elsif (today_day.schengen_days_count || 0) >= 80
                  'warning'
                else
                  'safe'
                end,
        last_calculated_date: today_day.the_date,
        in_waiting_period: today_day.warning?,
        outside_schengen: !today_day.schengen?
      }

      if current_user_or_guest_user.visa_required? && today_day.schengen?
        if today_day.respond_to?(:visa_valid?) && today_day.respond_to?(:visa_entry_valid?)
          if today_day.visa.nil?
            @status_summary[:visa_status] = 'warning'
            @status_summary[:visa_issue_type] = 'no_visa'
          elsif !today_day.visa_entry_valid?
            @status_summary[:visa_status] = 'warning'
            @status_summary[:visa_issue_type] = 'entry_limit_exceeded'
          elsif !today_day.visa_valid?
            @status_summary[:visa_status] = 'warning'
          else
            @status_summary[:visa_status] = 'ok'
          end

          if today_day.respond_to?(:has_limited_entries?) && today_day.has_limited_entries?
            @status_summary[:visa_entries_display] = "#{today_day.visa_entry_count}/#{today_day.visa_entries_allowed}"
            if today_day.respond_to?(:visa_entry_count) && today_day.respond_to?(:visa_entries_allowed)
              @status_summary[:visa_entries_exceeded] = today_day.visa_entry_count > today_day.visa_entries_allowed
            end
          end
        end
      end
    end
    # Use callbacks to share common setup or constraints between actions.
    def set_visit
      @visit = current_user_or_guest_user.visits.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def visit_params
      params.require(:visit).permit(:entry_date, :exit_date, :country_id)
    end

    def set_country_continent
      @continent = Continent.all
      @continent_default_id = Continent.find_by(continent_code: 'EU').id.to_s
      @country_options = Country.all.order_by_name.to_json(:only => [:id, :name, :continent_id])
    end
    
    def set_visits_meta_tags
      # More specific title for visits page
      @meta_title = I18n.t('visits.page_title') + ' | ' + I18n.t('common.schengen_calculator')
      @meta_description = I18n.t('visits.meta_description', default: I18n.t('default_description'))
      @og_type = 'website'
      @og_url = "https://#{request.host_with_port}#{request.path}"
      # Use schengen map image for visits page
      image_path = view_context.asset_path('schengen_area_eu_countries.webp')
      @og_image = "https://#{request.host_with_port}#{image_path}"
      @og_site_name = "Schengen Calculator"
      
      # Structured data for visits page
      @json_ld_data = {
        "@context" => "https://schema.org",
        "@type" => "WebPage",
        "name" => @meta_title,
        "description" => @meta_description,
        "url" => @og_url,
        "breadcrumb" => {
          "@type" => "BreadcrumbList",
          "itemListElement" => [
            {
              "@type" => "ListItem",
              "position" => 1,
              "name" => "Home",
              "item" => "https://#{request.host_with_port}/"
            },
            {
              "@type" => "ListItem",
              "position" => 2,
              "name" => I18n.t('visits.page_title'),
              "item" => @og_url
            }
          ]
        },
        "mainEntity" => {
          "@type" => "SoftwareApplication",
          "name" => I18n.t('common.schengen_calculator'),
          "applicationCategory" => "UtilityApplication",
          "description" => I18n.t('visits.page_description', default: I18n.t('default_description'))
        }
      }
    end
end
