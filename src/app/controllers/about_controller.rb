class AboutController < ApplicationController

  # GET /about/
  # GET /about/:nationaity
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
    
    # Set SEO meta tags for about page
    set_about_meta_tags
    
    @country = nil
    return if params[:nationality].nil?
    nationality = params[:nationality]
    nationality.gsub("_", " ")
    @country = Country.find_by_nationality(nationality)
               .outside_schengen.first
    fail ActionController::RoutingError, 'Page Not Found' if @country.nil?
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
  
  def set_about_meta_tags
    @meta_title = I18n.t('about.page_title', default: 'About') + ' | ' + I18n.t('common.schengen_calculator')
    @meta_description = I18n.t('about.meta_description', default: I18n.t('default_description'))
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    image_path = view_context.asset_path('schengen_area_eu_countries.webp')
    @og_image = "https://#{request.host_with_port}#{image_path}"
    @og_site_name = I18n.t('common.schengen_calculator')
    
    # Add JSON-LD structured data for about page
    @json_ld_data = {
      "@context" => "https://schema.org",
      "@type" => "AboutPage",
      "name" => @meta_title,
      "description" => @meta_description,
      "url" => @og_url,
      "breadcrumb" => {
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          {
            "@type" => "ListItem",
            "position" => 1,
            "name" => "Home",
            "item" => "https://#{request.host_with_port}/"
          },
          {
            "@type" => "ListItem",
            "position" => 2,
            "name" => "About",
            "item" => @og_url
          }
        ]
      },
      "mainEntity" => {
        "@type" => "WebApplication",
        "name" => I18n.t('common.schengen_calculator'),
        "applicationCategory" => "UtilityApplication",
        "operatingSystem" => "Any",
        "offers" => {
          "@type" => "Offer",
          "price" => "0",
          "priceCurrency" => "USD"
        }
      }
    }
  end
  
  def set_page_meta_tags(page_name)
    @meta_title = "#{page_name} - #{I18n.t('common.schengen_calculator')}"
    @meta_description = I18n.t('default_description')
    @og_type = 'website'
    @og_url = "https://#{request.host_with_port}#{request.path}"
    image_path = view_context.asset_path('schengen_area_eu_countries.webp')
    @og_image = "https://#{request.host_with_port}#{image_path}"
    @og_site_name = I18n.t('common.schengen_calculator')
  end
end
