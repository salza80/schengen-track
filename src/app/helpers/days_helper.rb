# frozen_string_literal: true

# Helper methods for days calendar view
module DaysHelper
  def day_country_name(day)
    return day.stayed_country.name if day.stayed_country

    if day.entered_country && day.exited_country
      if day.entered_country == day.exited_country
        return t('days.country_labels.same_day_trip', country: day.entered_country.name)
      end

      return t('days.country_labels.country_change', entered_country: day.entered_country.name,
               exited_country: day.exited_country.name)
    end

    (day.entered_country || day.exited_country)&.name || t('days.legend_outside')
  end

  # Returns CSS class for day cell based on status
  def day_cell_class(day)
    # Check for critical violations first
    return 'overstay' if day.danger?
    return 'overstay' if day.respond_to?(:visa_warning?) && day.visa_warning?
    return 'waiting-period' if day.warning?

    return 'in-schengen-safe' if day.schengen?
    return 'outside-schengen' if day.hasCountry?

    'no-travel'
  end

  # Generates tooltip text for day cell
  def day_tooltip(day)
    parts = []

    parts << content_tag(:strong, day_country_name(day)) if day.hasCountry?

    if day.freedom_of_movement?
      parts << t('days.tooltip.no_schengen_limit')
      return safe_join(parts, tag.br)
    end
    
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
    else
      # No calculation yet - show 0 days used for Schengen countries
      parts << t('days.tooltip.days_used', count: 0, default: "Days used: 0/90") if day.schengen?
    end
    
    # Show max remaining days
    remaining_days = day.max_remaining_days || (day.schengen? ? 90 : nil)
    if remaining_days&.positive? && day.the_date
      exit_date = l(day.the_date + remaining_days - (day.schengen? ? 0 : 1), format: :long)
      exit_date_span = content_tag(:span, exit_date, style: 'white-space: nowrap;')
      parts << t('days.tooltip.can_stay_html', days: remaining_days, date: exit_date_span).html_safe
    end

    warnings = day_warnings(day)
    parts << content_tag(:span, "⚠️ #{warnings[:overstay]}", class: 'text-danger') if warnings[:overstay]
    parts << content_tag(:span, "⏱ #{warnings[:wait]}", class: 'text-warning') if warnings[:wait]

    safe_join(parts, tag.br)
  end

  # Shared presentation for calendar tooltips and the editable visit's entry date.
  def day_warnings(day)
    return {} unless day

    {
      overstay: (t('days.tooltip.overstay', days: day.overstay_days) if day.overstay_days.positive?),
      wait: (t('days.tooltip.wait', days: day.remaining_wait) if day.remaining_wait)
    }.compact
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
    when 'safe' then 'text-bg-success'
    when 'warning' then 'text-bg-warning'
    when 'overstay' then 'text-bg-danger'
    else 'text-bg-info'
    end
  end

  # Checks if a day is today
  def is_today?(day)
    day && day.the_date == Time.zone.today
  end
end
