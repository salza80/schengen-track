require 'cgi'

class AboutController < ApplicationController

  # GET /about/
  # GET /about/:nationaity
  def about
    if current_user_or_guest_user.is_guest?
      expires_in 1.month, public: true
    end 
    @country = nil
    return if params[:nationality].nil?
    parsedNationality = CGI.unescape(params[:nationality]).downcase
    parsedNationality = parsedNationality.gsub!(" ", "_") if parsedNationality.include? " "
    return if parsedNationality.nil?
    @country = Country.find_by_nationality(parsedNationality)
               .outside_schengen.first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?
  end

  # GET /disclaimer/
  def disclaimer
  end
end
