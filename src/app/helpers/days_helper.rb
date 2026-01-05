# frozen_string_literal: true

# Helper methods for days calendar view
module DaysHelper
  # Returns CSS class for day cell based on status
  def day_cell_class(day)
    # Check for critical violations first
    return 'overstay' if day.danger?
    return 'overstay' if day.respond_to?(:visa_warning?) && day.visa_warning?
    return 'waiting-period' if day.warning?

    return 'in-schengen-safe' if day.schengen?

    'outside-schengen'
  end

  # Generates tooltip text for day cell
  def day_tooltip(day)
    parts = []

    parts << content_tag(:strong, day.country_name) if day.hasCountry?
    
    # Visa information (if applicable)
    if day.respond_to?(:user_requires_visa?) && day.user_requires_visa?
      if day.schengen?
        if day.visa.nil?
          parts << content_tag(:span, "⚠️ #{t('days.tooltip.no_visa')}", class: 'text-danger')
        elsif !day.visa_valid?
          parts << content_tag(:span, "⚠️ #{t('days.tooltip.outside_visa')}", class: 'text-danger')
        else
          parts << content_tag(:span, "✓ #{t('days.tooltip.valid_visa')}", class: 'text-success')
          if day.has_limited_entries?
            if day.visa_entry_valid?
              parts << t('days.tooltip.entries', count: day.visa_entry_count, total: day.visa_entries_allowed)
            else
              parts << content_tag(:span, "⚠️ #{t('days.tooltip.entries_exceeded', count: day.visa_entry_count, total: day.visa_entries_allowed)}", class: 'text-danger')
            end
          end
        end
      end
    end
    
    # Schengen day count
    if day.schengen_days_count
      parts << t('days.tooltip.days_used', count: day.schengen_days_count, default: "Days used: #{day.schengen_days_count}/90")
    end
    if day.max_remaining_days && day.the_date
      exit_date = l(day.the_date + (day.max_remaining_days - 1).days, format: :long)
      exit_date_span = content_tag(:span, exit_date, style: 'white-space: nowrap;')
      parts << t('days.tooltip.can_stay_html', days: day.max_remaining_days, date: exit_date_span).html_safe
    end

    if day.overstay_days.positive?
      parts << content_tag(:span, "⚠️ #{t('days.tooltip.overstay', days: day.overstay_days)}", class: 'text-danger')
    end

    parts << content_tag(:span, "⏱ #{t('days.tooltip.wait', days: day.remaining_wait)}", class: 'text-warning') if day.remaining_wait

    safe_join(parts, tag.br)
  end

  # Extracts 2-letter ISO code from day's country
  def country_iso_code(day)
    country = day.stayed_country || day.entered_country || day.exited_country
    return '' unless country

    # Use country_code field if available, otherwise extract first 2 letters of name
    country.country_code&.upcase || country.name[0..1].upcase
  end

  # Returns Bootstrap icon class for status
  def status_icon_class(status)
    case status.to_s
    when 'safe'
      'fa-check-circle text-success'
    when 'warning'
      'fa-exclamation-triangle text-warning'
    when 'overstay'
      'fa-times-circle text-danger'
    else
      'fa-info-circle text-info'
    end
  end

  # Returns Bootstrap text color class for status
  def status_text_class(status)
    case status.to_s
    when 'safe' then 'success'
    when 'warning' then 'warning'
    when 'overstay' then 'danger'
    else 'info'
    end
  end

  # Returns Bootstrap badge class for status
  def status_badge_class(status)
    case status.to_s
    when 'safe' then 'badge-success'
    when 'warning' then 'badge-warning'
    when 'overstay' then 'badge-danger'
    else 'badge-info'
    end
  end

  # Checks if a day is today
  def is_today?(day)
    day && day.the_date == Time.zone.today
  end
end
