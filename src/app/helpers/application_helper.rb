module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.titleize }
  end

  def active_if(options)
    'active' if params.merge(options) == params
  end

  def get_started_path
    # Check if user requires visa - if so, send to visits page
    # Otherwise, send to calendar/days page with current year
    if current_user_or_guest_user&.visa_required?
      visits_path(locale: I18n.locale)
    else
      days_path(locale: I18n.locale, year: Date.today.year)
    end
  end

  def language_selector
    locales = Rails.application.config.i18n.available_locales
    current_locale = I18n.locale.to_sym
  
    content_tag(:select, class: 'language-select form-control form-control-sm', onchange: 'window.location.href = this.value;') do
      locales.map do |locale|
        option_url = url_for(locale: locale)
        content_tag(:option, locale.upcase, value: option_url, selected: locale == current_locale)
      end.join.html_safe
    end
  end

  # Generate breadcrumb JSON-LD structured data
  def breadcrumb_schema(breadcrumbs)
    items = breadcrumbs.each_with_index.map do |crumb, index|
      {
        '@type': 'ListItem',
        position: index + 1,
        name: crumb[:name],
        item: crumb[:url]
      }
    end

    schema = {
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      itemListElement: items
    }

    content_tag(:script, type: 'application/ld+json') do
      schema.to_json.html_safe
    end
  end

  # Helper to render breadcrumb navigation with schema
  def render_breadcrumbs(breadcrumbs)
    content = content_tag(:nav, class: 'breadcrumbs', 'aria-label': 'Breadcrumb') do
      content_tag(:ol) do
        breadcrumbs.each_with_index.map do |crumb, index|
          content_tag(:li, class: (index == breadcrumbs.length - 1 ? 'active' : '')) do
            if index == breadcrumbs.length - 1
              crumb[:name]
            else
              link_to(crumb[:name], crumb[:url])
            end
          end
        end.join.html_safe
      end
    end

    # Return both navigation and schema
    content + breadcrumb_schema(breadcrumbs)
  end
end
