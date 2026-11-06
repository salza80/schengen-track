class CalculationLinksController < ApplicationController
  include SensitiveTokenResponse
  include GuestCalculatorAbuseControl

  def show
    AgentCalculations::Claim.find_available_source!(params[:token])
    @token = params[:token]
  rescue AgentCalculations::Claim::Unavailable
    invalid_link
  end

  def create
    result = AgentCalculations::Claim.new(
      token: params[:token], account: current_user, guest: guest_user
    ).call

    if current_user
      session[:current_person_id] = result.person.id
    else
      establish_guest_session(result.user, result.person)
    end
    redirect_to private_days_path(short_link_redirect_params(result.person)), status: :see_other
  rescue AgentCalculations::Claim::TooLarge
    redirect_to root_path(locale: I18n.default_locale), alert: t('calculation_claim.too_large'), status: :see_other
  rescue AgentCalculations::Claim::Unavailable, ActiveRecord::RecordInvalid
    invalid_link
  end

  private

  def invalid_link
    redirect_to root_path(locale: I18n.default_locale), alert: t('calculation_claim.invalid'), status: :see_other
  end

  def short_link_redirect_params(person)
    params = { locale: I18n.default_locale }
    first_entry = person&.visits&.minimum(:entry_date)
    return params unless first_entry

    params.merge(year: first_entry.year, month: first_entry.month, day: first_entry.day)
  end
end
