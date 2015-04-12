class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_person

  def current_person
    if user_signed_in?
      current_user.people.first
    end
  end
end
