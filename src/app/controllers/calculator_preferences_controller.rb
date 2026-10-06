class CalculatorPreferencesController < ApplicationController
  before_action :set_private_calculator_cache
  def update
    destination = %w[trips calendar].include?(params[:destination]) ? params[:destination] : 'trips'

    if anonymous_calculator?
      nationality = Country.find_by(id: params[:nationality_id])
      unless nationality
        redirect_to destination_path(destination), alert: t('common.invalid_nationality')
        return
      end

      session[:calculator_nationality_id] = nationality.id
    end

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
