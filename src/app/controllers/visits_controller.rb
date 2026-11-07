class VisitsController < ApplicationController
  include GuestCalculatorAbuseControl
  include CalculatorVisits
  include CalculatorIndexCache
  before_action :limit_guest_reads!, only: [:index, :for_date, :max_stay_info]
  before_action :set_private_calculator_cache, except: :index
  
  before_action :require_calculator_record_account!, only: [:show, :edit, :update, :destroy]
  before_action :set_visit, only: [:show, :edit, :update, :destroy]
  before_action :set_country_options, only: [:new, :edit, :update, :create]
  #before_action :authenticate_user!
  
  # Handle RecordNotFound errors (e.g., visit doesn't belong to current person)
  rescue_from ActiveRecord::RecordNotFound, with: :visit_not_found
  
  # Skip CSRF verification for .js GET requests (new, edit, for_date, max_stay_info)
  # These are safe read-only operations that need to work with AJAX
  skip_before_action :verify_authenticity_token, only: [:new, :edit, :for_date, :max_stay_info], if: -> { request.format.js? || request.format.json? }

  # GET /visits
  # GET /visits.json
  def index
    calc = Schengen::Calculator.new(current_person, visits: calculator_visits)
    @visits = calc.visits
    if current_person.visa_required?
      @visas = current_person.visas.all
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
      format.csv do
        csv = calc.to_csv
        Analytics::GoogleMeasurementProtocol.track(
          'user_csv_export',
          request: request,
          params: {
            category: 'visits',
            action: 'csv_export',
            value: 1
          }
        )
        send_data csv
      end
    end
  end
  # GET /visits/1
  # GET /visits/1.json
  def show
  end

  # GET /visits/new
  def new
    @visit = Visit.with_default(current_person, visits: calculator_visits)
    
    # Support pre-filling dates from calendar clicks
    if params[:entry_date]
      @visit.entry_date = Date.parse(params[:entry_date])
      @visit.exit_date = params[:exit_date] ? Date.parse(params[:exit_date]) : @visit.entry_date + 1.day
    end
    
    respond_to do |format|
      format.js   # Trips dialog
      format.json { render_visit_form(t('visits.add_record')) }
    end
  end

  # GET /visits/1/edit
  def edit
    if @visit.country && !@visit.country.affiliate_booking_html.nil?
      @advertise_country = @visit.country
    end
    
    respond_to do |format|
      format.js   # Trips dialog
      format.json { render_visit_form(t('visits.edit_title')) }
    end
  end

  # POST /visits
  # POST /visits.json
  def create
    if anonymous_calculator?
      return render_calculator_nationality_required(open_trip: true) unless calculator_nationality_selected?

      result = AnonymousCalculator::FirstSave.call(
        nationality: calculator_nationality_record,
        record_class: Visit,
        attributes: visit_params
      )
      @visit = result.record
      establish_guest_session(result.user, result.person) if result.success?
    else
      @visit = current_person.visits.build(visit_params)
      @visit.save
    end

    if @visit.persisted?
      Analytics::GoogleMeasurementProtocol.track(
        'user_add_visit',
        request: request,
        params: {
          category: 'visits',
          action: 'add_visit',
          value: 1
        }
      )
    end

    respond_to do |format|
      if @visit.persisted?
        format.html { redirect_to calculator_visits_path, notice: 'Visit was successfully created.' }
        format.json do
          if request.xhr?
            render json: { saved: true }, status: :created, location: @visit
          else
            render :show, status: :created, location: @visit
          end
        end
        format.js   # Trips dialog
      else
        format.html { render :new }
        format.json do
          if request.xhr?
            render_visit_form(t('visits.add_record'), status: :unprocessable_entity)
          else
            render json: @visit.errors, status: :unprocessable_entity
          end
        end
        format.js   # Trips dialog validation errors
      end
    end
  end

  # PATCH/PUT /visits/1
  # PATCH/PUT /visits/1.json
  def update
    respond_to do |format|
      if @visit.update(visit_params)
        format.html { redirect_to calculator_visits_path, notice: 'Visit was successfully updated.' }
        format.json do
          request.xhr? ? render(json: { saved: true }) : render(:show, status: :ok, location: @visit)
        end
        format.js   # Trips dialog
      else
        format.html { render :edit }
        format.json do
          if request.xhr?
            render_visit_form(t('visits.edit_title'), status: :unprocessable_entity)
          else
            render json: @visit.errors, status: :unprocessable_entity
          end
        end
        format.js   # Trips dialog validation errors
      end
    end
  end

  # DELETE /visits/1
  # DELETE /visits/1.json
  def destroy
    # Store entry date before destroying for fallback redirect
    entry_year = @visit.entry_date.year
    entry_month = @visit.entry_date.month
    
    @visit.destroy
    
    respond_to do |format|
      format.html { 
        # Try to redirect back to referer if it's from calendar page
        if request.referer.present?
          begin
            referer_uri = URI.parse(request.referer)
            
            # Only process referer if it's from our own domain (not external)
            if referer_uri.host.nil? || referer_uri.host == request.host
              referer_path = referer_uri.path
              referer_query = referer_uri.query
              
              # Check if coming from calendar page
              if referer_path.include?('/days')
                # Reconstruct the full calendar URL with query params
                redirect_url = referer_path
                redirect_url += "?#{referer_query}" if referer_query.present?
                
                # Validate it's a safe redirect
                if safe_redirect_path?(redirect_url)
                  redirect_to redirect_url, notice: 'Visit was successfully deleted.', allow_other_host: false
                  return
                end
              end
            end
          rescue URI::InvalidURIError
            # Invalid referer, fall through to default
          end
        end
        
        # Default fallback: redirect to visits list
        redirect_to calculator_visits_path(locale: I18n.locale), notice: 'Visit was successfully deleted.'
      }
      format.json { head :no_content }
    end
  end

  # GET /visits/for_date?date=YYYY-MM-DD
  # Returns all visits that include the specified date (for the calendar dialog)
  def for_date
    date = Date.parse(params[:date])
    visits = calculator_visits.find_by_date(date, date)
    
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
  
  # GET /visits/max_stay_info?date=YYYY-MM-DD&country_code=DE
  # Returns max stay information for a given entry date and country
  # Accepts legacy country_id as well; no country defaults to Schengen.
  def max_stay_info
    date = Date.parse(params[:date])
    next_visits = calculator_visits.where('entry_date > ?', date).order(:entry_date)
    next_visits = next_visits.where.not(id: params[:visit_id]) if params[:visit_id].present?
    next_visit = next_visits.first

    country = if params[:country_code].present?
                Country.find_by!(country_code: params[:country_code].to_s.upcase)
              elsif params[:country_id].present?
                Country.find(params[:country_id])
              end
    is_schengen = country.nil? || country.schengen?(date)
    entry_info = nil
    remaining = nil

    if is_schengen && current_person.nationality.visa_required != 'F'
      visa_history = Schengen::VisaHistory.new(current_person) if current_person.visa_required?
      calculator = Schengen::Days::Calculator.new(current_person, visits: calculator_visits, visa_history: visa_history)
      day = calculator.find_by_date(date)
      remaining = day.nil? ? 90 : day.max_remaining_days
      entry_info = visit_entry_info(date, day, visa_history)
    end

    exit_date = date + (remaining - 1).days if remaining&.positive?
    result = { show: false, entry_info: entry_info }
    # A later trip cannot grant days when the Schengen allowance is exhausted.
    blocked = remaining && remaining <= 0
    if !blocked && next_visit && (exit_date.nil? || exit_date >= next_visit.entry_date)
      result.merge!(show: true, max_days: (next_visit.entry_date - date).to_i,
                    exit_date: I18n.l(next_visit.entry_date - 1.day, format: :long),
                    exit_date_iso: (next_visit.entry_date - 1.day).iso8601,
                    constrained: true, constraint_type: 'next_visit',
                    next_entry_date: I18n.l(next_visit.entry_date, format: :long))
    elsif exit_date
      result.merge!(show: true, max_days: remaining, exit_date: I18n.l(exit_date, format: :long),
                    exit_date_iso: exit_date.iso8601, constrained: true, constraint_type: 'schengen')
    end
    render json: result
  end

  private
    def visit_entry_info(date, day, visa_history)
      info = { days_used: t('days.tooltip.days_used', count: day&.schengen_days_count || 0) }
        .merge(helpers.day_warnings(day))
      return info unless visa_history

      visa = visa_history.visa_for_date(date)
      info[:visa_missing] = visa.nil?
      info[:visa_status] = visa ? t('days.tooltip.valid_visa') : t('visits.no_visa_for_date')
      if visa && visa.no_entries.positive?
        count = visa_history.entry_count_on(date, visa)
        info[:visa_entries_exceeded] = count > visa.no_entries
        key = info[:visa_entries_exceeded] ? 'days.tooltip.entries_exceeded' : 'days.tooltip.entries'
        info[:visa_entries] = t(key, count: count, total: visa.no_entries)
      end
      info
    end

    def render_visit_form(title, status: :ok)
      render json: {
        html: render_to_string(partial: 'visits/form', formats: [:html]),
        title: title,
        save_label: t('common.save'),
        errors: @visit.errors
      }, status: status
    end

    def setup_sidebar_data(calc)
      @days = calc.calculated_days
      @overstay = calc.schengen_overstay?
      calculate_status_summary_for_visits
    end

    def calculate_status_summary_for_visits
      return unless @days&.any?

      today = Time.zone.today
      today_day = @days.find { |d| d.the_date == today } || @days.max_by(&:the_date)

      @status_summary = {
        current_days: today_day.schengen_days_count || 0,
        max_days: 90,
        remaining_days: today_day.max_remaining_days || [90 - (today_day.schengen_days_count || 0), 0].max,
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

      if current_person.visa_required? && today_day.schengen?
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
      @visit = current_person.visits.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def visit_params
      permitted = params.require(:visit).permit(:entry_date, :exit_date, :country_id, :country_code)
      if permitted.key?(:country_code)
        country_code = permitted.delete(:country_code)
        # An explicit blank clears the association for validation; omission
        # preserves it for partial updates and legacy country_id submissions.
        permitted[:country_id] = country_code.present? ? Country.find_by(country_code: country_code.to_s.upcase)&.id : nil
      end
      permitted
    end

    def set_country_options
      @country_options = CountryCatalog.country_options.to_json
    end
    
    def set_visits_meta_tags
      # More specific title for visits page
      @meta_title = I18n.t('visits.page_title') + ' | ' + I18n.t('common.schengen_calculator')
      @meta_description = I18n.t('visits.meta_description', default: I18n.t('default_description'))
      @og_type = 'website'
      @og_url = "https://#{request.host_with_port}#{seo_canonical_path}"
      # Use schengen map image for visits page
      image_path = view_context.asset_path('schengen_area_eu_countries.webp')
      @og_image = "https://#{request.host_with_port}#{image_path}"
      @og_site_name = I18n.t('common.schengen_calculator')
      localized_home_url = view_context.seo_url('/', locale: I18n.locale)
      
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
              "name" => I18n.t('common.home'),
              "item" => localized_home_url
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
          "applicationCategory" => "UtilitiesApplication",
          "description" => I18n.t('visits.page_description', default: I18n.t('default_description'))
        }
      }
    end
    
    # Handle visit not found (doesn't exist or doesn't belong to current person)
    def visit_not_found
      respond_to do |format|
        format.html { 
          redirect_to calculator_visits_path(locale: I18n.locale),
                      alert: 'Visit not found or you do not have permission to access it.'
        }
        format.json { render json: { error: 'Visit not found' }, status: :not_found }
        format.js { 
          flash[:alert] = 'Visit not found or you do not have permission to access it.'
          url = visits_path(locale: I18n.locale)
          render js: "window.location.href = #{url.to_json};"
        }
      end
    end

    # Validate redirect path to prevent open redirect vulnerabilities
    # Only allows relative paths within the application
    def safe_redirect_path?(path)
      return false if path.blank?
      
      # Reject protocol-relative URLs before parsing (defense-in-depth)
      # While URI.parse would catch these, explicit early rejection is clearer and faster
      return false if path.start_with?('//')
      
      uri = URI.parse(path)
      
      # Reject if it has a scheme (http://, https://, javascript:, etc.)
      return false if uri.scheme.present?
      
      # Reject if it has a host
      return false if uri.host.present?
      
      # Only allow paths starting with /
      return false unless path.start_with?('/')
      
      # Whitelist specific application paths for defense-in-depth
      # Using start_with? intentionally allows sub-paths and query params:
      #   ✓ /days/2024/12
      #   ✓ /en/days?year=2025&month=1&day=15
      #   ✓ /visits/123/edit
      allowed_paths = ['/days', '/visits', '/people', '/visas', '/my/days', '/my/visits']
      I18n.available_locales.each do |locale|
        allowed_paths += ["/#{locale}/days", "/#{locale}/visits", "/#{locale}/people", "/#{locale}/visas",
                          "/#{locale}/my/days", "/#{locale}/my/visits"]
      end
      
      return false unless allowed_paths.any? { |allowed| path.start_with?(allowed) }
      
      true
    rescue URI::InvalidURIError
      false
    end
end
