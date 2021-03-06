class AboutController < ApplicationController

  # GET /about/
  # GET /about/:nationaity
  def about
    @country = nil
    return if params[:nationality].nil?
    @country = Country.find_by_nationality(params[:nationality])
               .outside_schengen.first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?
  end

  # GET /disclaimer/
  def disclaimer
  end
end
