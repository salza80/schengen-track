class CalculationLinksController < ApplicationController
  def show
    user = User.find_signed!(params[:token], purpose: :agent_calculation)

    session[:guest_user_id] = user.id if user.is_guest?
    person = user.people.where(is_primary: true).first || user.people.first
    session[:current_person_id] = person&.id

    redirect_to days_path(short_link_redirect_params(person))
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path(locale: I18n.default_locale), alert: 'Calculation link is invalid or has expired.'
  end

  private

  def short_link_redirect_params(person)
    params = { locale: I18n.default_locale }
    first_entry = person&.visits&.minimum(:entry_date)
    return params unless first_entry

    params.merge(year: first_entry.year, month: first_entry.month, day: first_entry.day)
  end
end
