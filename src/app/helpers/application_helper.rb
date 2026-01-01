module ApplicationHelper
  # List of RTL (Right-to-Left) locales
  RTL_LOCALES = [:ar].freeze

  def title(page_title)
    content_for(:title) { page_title.titleize }
  end

  def active_if(options)
    'active' if params.merge(options) == params
  end

  # Check if the current locale uses RTL layout
  def rtl_locale?
    RTL_LOCALES.include?(I18n.locale)
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
    
    locale_names = {
      en: 'English',
      de: 'Deutsch',
      es: 'Español',
      hi: 'हिन्दी',
      tr: 'Türkçe',
      'zh-CN': '中文',
      'pt-BR': 'Português',
      ar: 'العربية'
    }
  
    # Return both dropdown (for users) and hidden links (for SEO)
    dropdown = content_tag(:select, class: 'language-select form-control form-control-sm', onchange: 'window.location.href = this.value;', 'aria-label': 'Select language') do
      locales.map do |locale|
        option_url = url_for(locale: locale)
        locale_display = "#{locale.to_s.upcase} - #{locale_names[locale.to_sym]}"
        content_tag(:option, locale_display, value: option_url, selected: locale == current_locale)
      end.join.html_safe
    end
    
    # Hidden links for search engine crawlers (visually hidden but accessible to screen readers)
    seo_links = content_tag(:div, class: 'language-links-seo', style: 'position:absolute;left:-9999px;') do
      locales.map do |locale|
        next if locale == current_locale
        link_url = url_for(locale: locale)
        link_to(locale_names[locale.to_sym] || locale.to_s.upcase, link_url, hreflang: locale.to_s, lang: locale.to_s)
      end.compact.join(' | ').html_safe
    end
    
    dropdown + seo_links
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

  # Inline critical CSS for above-the-fold rendering
  # Minified in all environments to catch issues early
  # See app/assets/stylesheets/critical.css for readable source with comments
  def critical_css
    # In production, cache the result in Rails.cache since file never changes
    # In development, use instance variable to allow file changes during development
    cache_key = 'critical_css_minified'
    
    if Rails.env.production?
      Rails.cache.fetch(cache_key) do
        minify_critical_css
      end
    else
      @critical_css ||= minify_critical_css
    end
  end

  private

  def minify_critical_css
    css_content = File.read(Rails.root.join('app/assets/stylesheets/critical.css'))
    
    # Minify: remove comments and collapse whitespace
    css_content.gsub(/\/\*.*?\*\//m, '')       # Remove /* comments */
               .gsub(/\s+/, ' ')                # Collapse whitespace
               .gsub(/\s*([{}:;,])\s*/, '\1')  # Remove space around punctuation
               .strip
  end
end
