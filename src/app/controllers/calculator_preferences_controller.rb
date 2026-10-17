class CalculatorPreferencesController < ApplicationController
  before_action :set_private_calculator_cache
  def update
    destination = %w[trips calendar].include?(params[:destination]) ? params[:destination] : 'trips'
    nationality_selected = false

    if anonymous_calculator?
      country_entry = CountryCatalog.find_by_code(params[:nationality_code])

      # Compatibility for forms cached before country codes were introduced.
      if country_entry.nil? && params[:nationality_id].present?
        legacy_country = Country.find_by(id: params[:nationality_id])
        country_entry = CountryCatalog.find_by_code(legacy_country&.country_code)
      end

      unless country_entry
        redirect_to destination_path(destination), alert: t('common.invalid_nationality')
        return
      end

      session[:calculator_nationality_code] = country_entry.country_code
      session.delete(:calculator_nationality_id)
      nationality_selected = true
    end

    set_session_hint if nationality_selected
    redirect_to destination_path(destination)
  end

  private

  def destination_path(destination)
    continuation = params[:open] == 'trip' ? { open: 'trip' } : {}
    return visits_path({ locale: I18n.locale }.merge(continuation)) unless destination == 'calendar'

    date_params = params.permit(:year, :month, :day, :entry_date, :exit_date).to_h.compact_blank
    days_path({ locale: I18n.locale }.merge(date_params).merge(continuation))
  end
end
