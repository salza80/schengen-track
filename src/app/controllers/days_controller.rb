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
    end
  end

  private
  
end
