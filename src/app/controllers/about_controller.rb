class AboutController < ApplicationController
  LAST_REVIEWED_DATE = Date.new(2026, 5, 30).freeze

  # GET /about/
  # GET /about/:nationality
  def about
    if current_user_or_guest_user.is_guest?
      if Rails.env.development?
        # In development, prevent browser caching to match production behavior
        # (Production: CloudFront's ResponseHeadersPolicy overrides Cache-Control to no-cache)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      else
        # Tell CloudFront to cache for 1 month (only in production)
        expires_in 1.month, public: true
      end
    end
    
    set_country_from_params
    set_about_meta_tags
  end

  # GET /disclaimer/
  def disclaimer
    set_page_meta_tags('Disclaimer')
  end
  
  # GET /privacy/
  def privacy
    set_page_meta_tags('Privacy Policy')
  end
  
  private

  def set_country_from_params
    @country = nil
    return if params[:nationality].blank?

    nationality = params[:nationality].to_s.downcase.tr(' ', '_')
    @country = Country.find_by_nationality(nationality)
                      .outside_schengen
                      .first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?
  end
  
  def set_about_meta_tags
    @last_reviewed_date = LAST_REVIEWED_DATE

    if @country
      nationality_title = I18n.t('about.nationality.tourist_travel_requirements_title',
                                 nationality_plural: @country.nationality_plural)
      @meta_title = "#{nationality_title} | #{I18n.t('common.schengen_calculator')}"
      @meta_description = "#{nationality_visa_requirement_text(@country)} #{I18n.t('default_description')}".squish.truncate(160)
    else
      @meta_title = I18n.t('about.page_title', default: 'About') + ' | ' + I18n.t('common.schengen_calculator')
      @meta_description = I18n.t('about.meta_description', default: I18n.t('default_description'))
    end
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    @og_image = absolute_asset_url('schengen_area_eu_countries.webp')
    @og_site_name = I18n.t('common.schengen_calculator')
    
    @json_ld_data = [
      about_page_schema,
      faq_schema
    ]
  end

  def about_page_schema
    page_url = canonical_url(request.path)

    schema = {
      "@context" => "https://schema.org",
      "@type" => "AboutPage",
      "@id" => "#{page_url}#webpage",
      "name" => @meta_title,
      "description" => @meta_description,
      "url" => page_url,
      "inLanguage" => I18n.locale.to_s,
      "dateModified" => LAST_REVIEWED_DATE.iso8601,
      "lastReviewed" => LAST_REVIEWED_DATE.iso8601,
      "citation" => ABOUT_OFFICIAL_SOURCE_URLS,
      "isPartOf" => {
        "@type" => "WebSite",
        "@id" => "#{CANONICAL_SITE_URL}/#website",
        "name" => I18n.t('common.schengen_calculator'),
        "url" => "#{CANONICAL_SITE_URL}/"
      },
      "publisher" => organization_schema(include_logo: true),
      "breadcrumb" => {
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          {
            "@type" => "ListItem",
            "position" => 1,
            "name" => "Home",
            "item" => canonical_url('/')
          },
          {
            "@type" => "ListItem",
            "position" => 2,
            "name" => "About",
            "item" => page_url
          }
        ]
      },
      "mainEntity" => {
        "@type" => "WebApplication",
        "@id" => "#{CANONICAL_SITE_URL}/#app",
        "name" => I18n.t('common.schengen_calculator'),
        "url" => "#{CANONICAL_SITE_URL}/",
        "description" => I18n.t('default_description'),
        "applicationCategory" => "UtilityApplication",
        "operatingSystem" => "Any",
        "offers" => {
          "@type" => "Offer",
          "price" => "0",
          "priceCurrency" => "USD"
        }
      }
    }

    if @country
      schema["about"] = [
        {
          "@type" => "Thing",
          "name" => "Schengen Area"
        },
        {
          "@type" => "Country",
          "name" => @country.name
        }
      ]
    end

    schema
  end

  def faq_schema
    {
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "@id" => "#{canonical_url(request.path)}#faq",
      "inLanguage" => I18n.locale.to_s,
      "mainEntity" => (1..10).map do |index|
        {
          "@type" => "Question",
          "name" => I18n.t("about.about.faq.q#{index}.question"),
          "acceptedAnswer" => {
            "@type" => "Answer",
            "text" => I18n.t("about.about.faq.q#{index}.answer")
          }
        }
      end
    }
  end
  
  def set_page_meta_tags(page_name)
    @meta_title = "#{page_name} - #{I18n.t('common.schengen_calculator')}"
    @meta_description = I18n.t('default_description')
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    @og_image = absolute_asset_url('schengen_area_eu_countries.webp')
    @og_site_name = I18n.t('common.schengen_calculator')
  end

  def nationality_visa_requirement_text(country)
    case country.visa_required
    when 'F'
      I18n.t('about.nationality.visa_not_required', country: country.name)
    when 'V'
      I18n.t('about.nationality.visa_required', country: country.name)
    else
      I18n.t('about.nationality.visa_exempt', country: country.name)
    end
  end

end
