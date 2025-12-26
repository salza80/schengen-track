# frozen_string_literal: true

# Helper methods for days calendar view
module DaysHelper
  # Returns CSS class for day cell based on status
  def day_cell_class(day)
    # Check for critical violations first
    return 'overstay' if day.danger?
    return 'overstay' if day.respond_to?(:visa_warning?) && day.visa_warning?
    return 'waiting-period' if day.warning?

    if day.schengen?
      'in-schengen-safe'
    else
      'outside-schengen'
    end
  end

  # Generates tooltip text for day cell
  def day_tooltip(day)
    parts = []

    parts << "<strong>#{day.country_name}</strong>" if day.hasCountry?
    
    # Visa information (if applicable)
    if day.respond_to?(:user_requires_visa?) && day.user_requires_visa?
      if day.schengen?
        if day.visa.nil?
          parts << "<span class='text-danger'>⚠️ NO VISA</span>"
        elsif !day.visa_valid?
          parts << "<span class='text-danger'>⚠️ Outside visa period</span>"
        else
          parts << "<span class='text-success'>✓ Valid visa</span>"
          if day.has_limited_entries?
            if day.visa_entry_valid?
              parts << "Entries: #{day.visa_entry_count}/#{day.visa_entries_allowed}"
            else
              parts << "<span class='text-danger'>⚠️ Entry limit exceeded: #{day.visa_entry_count}/#{day.visa_entries_allowed}</span>"
            end
          end
        end
      end
    end
    
    # Schengen day count
    parts << "Days used: #{day.schengen_days_count}/90" if day.schengen_days_count
    if day.max_remaining_days
      exit_date = (day.the_date + (day.max_remaining_days - 1).days).strftime('%b %d, %Y')
      parts << "Can stay: #{day.max_remaining_days} more days until #{exit_date}"
    end

    if day.overstay_days.positive?
      parts << "<span class='text-danger'>⚠️ SCHENGEN OVERSTAY: +#{day.overstay_days} days</span>"
    end

    parts << "<span class='text-warning'>⏱ Wait: #{day.remaining_wait} days</span>" if day.remaining_wait

    parts.join('<br>')
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
    day && day.the_date == Date.today
  end
end
