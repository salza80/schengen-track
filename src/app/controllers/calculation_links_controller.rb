class CalculationLinksController < ApplicationController
  def show
    user = User.find_signed!(params[:token], purpose: :agent_calculation)

    session[:guest_user_id] = user.id if user.is_guest?
    session[:current_person_id] = user.people.where(is_primary: true).first&.id || user.people.first&.id

    redirect_to days_path(locale: I18n.default_locale)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path(locale: I18n.default_locale), alert: 'Calculation link is invalid or has expired.'
  end
end
