module Aws
  class BookQuery

 
    COUNTRIES = {
      us: { tracking_code: 'schenecalcul-20', browse_node: '27' },
      uk: { tracking_code: 'schengcalcul-21', browse_node: nil }
    }

    def initialize(country_code)
      country_code = country_code.downcase
      country_code = 'uk' if country_code == 'gb'
      if country_valid?(country_code)
        @country_code = country_code.to_sym
      else
        @country_code = :us
      end

    end

    def query(search)
      options = {}
      options[:search_index] = 'Books'
      options[:associate_tag] = COUNTRIES[@country_code][:tracking_code]
      options[:Country] = @country_code
      options[:BrowseNode] = COUNTRIES[@country_code][:browse_node]
      search += ' travel' if  COUNTRIES[@country_code][:browse_node].nil?
      return nil if  Rails.env == 'test'
      begin
        resp = Amazon::Ecs.item_search(search, options)
      rescue => e
        Rails.logger.debug 'Amazon search failed for country code: ' + @country_code.to_s + ' cause: ' +   e.to_s
        return nil
      end
      return nil if resp.has_error?
      resp
    end

    def country_valid?(country_code)
      COUNTRIES.each do |key, _value|
        return true if key == country_code.to_sym
      end
      false
    end
  end
end
