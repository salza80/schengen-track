class VisitsController < ApplicationController
  before_action :set_visit, only: [:show, :edit, :update, :destroy]
  before_action :set_country_continent, only: [:new, :edit, :update, :create]
  #before_action :authenticate_user!

  # GET /visits
  # GET /visits.json
  def index
    puts Rails.application.secrets.facebook_id

    calc = Schengen::Calculator.new(current_user_or_guest_user)
    @visits = calc.visits
    @visas = current_user_or_guest_user.visas.all if current_user_or_guest_user.visa_required?
    @next_entry_days = calc.next_entry_days
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
    @visit.destroy
    respond_to do |format|
      format.html { redirect_to visits_path, notice: 'Visit was successfully deleted.' }
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

  private
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
end
