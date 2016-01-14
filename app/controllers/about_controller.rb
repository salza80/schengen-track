class AboutController < ApplicationController

  # GET /about/
  def about
  end

  # GET /disclaimer/
  def disclaimer
  end

  def nationality
    @country = Country.find_by_nationality(params[:nationality]).outside_schengen.first
    if @country.nil?
      fail ActionController::RoutingError, 'Page Not Found'
    end
  end
end
