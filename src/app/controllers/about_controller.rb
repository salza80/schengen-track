class AboutController < ApplicationController

  # GET /about/
  # GET /about/:nationaity
  def about
    @country = nil
    return if params[:nationality].nil?
    @country = Country.find_by_nationality(params[:nationality])
               .outside_schengen.first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?

    if current_user_or_guest_user.is_guest?
      response.headers['Cache-Control'] = 'public, max-age=3600'
    end
  end

  # GET /disclaimer/
  def disclaimer
  end
end
