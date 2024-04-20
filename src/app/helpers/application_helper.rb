module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.titleize }
  end

  def active_if(options)
    'active' if params.merge(options) == params
  end

  def language_selector
    locales = Rails.application.config.i18n.available_locales
    current_locale = I18n.locale.to_sym
  
    content_tag(:span) do
      locales.map do |locale|
        content_tag(:span, class: locale == current_locale ? 'active' : '') do
          link_to(locale.upcase, locale: locale)
        end
      end.join(" | ").html_safe
    end
  end
end
