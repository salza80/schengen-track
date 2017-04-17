class DaysController < ApplicationController
  before_action :set_visit, only: [:show, :edit, :update, :destroy]
  before_action :set_country_continent, only: [:new, :edit, :update, :create]
  #before_action :authenticate_user!

  # GET /visits
  # GET /visits.json
  def index
    if current_person.visa_required? 
      redirect_to visits_url
    else
      days_calc = Schengen::Days::Calculator.new(current_person)
      @days = days_calc.calculated_days
    end
  end

  private
  
end
