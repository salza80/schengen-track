module Aws
  class BookQuery

    COUNTRIES = {
      us: { tracking_code: 'schenecalcul-20', browse_node: '27' },
      uk: { tracking_code: 'schengcalcul-21', browse_node: '83' },
      ca: { tracking_code: 'schengcalcul-20', browse_node: nil }
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
      options[:country] = @country_code
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
      BookQueryReponse.new(resp.items)
    end

    private

    def country_valid?(country_code)
      COUNTRIES.each do |key, _value|
        return true if key == country_code.to_sym
      end
      false
    end

    class BookQueryReponse
      attr_reader :items
      
      def initialize(resp_items)
        array_resp = []
        resp_items.each do |item|
          item = BookItem.new(item)
          if item.valid?
            array_resp << item
          end
        end
        @items = array_resp
      end
    end

    class BookItem
      attr_reader :title, :price, :image_url, :page_url

      def initialize(resp_item)
        @page_url = parse_page_url(resp_item)
        @image_url = parse_image_url(resp_item)
        @title = parse_title(resp_item)
        @price = parse_price(resp_item)
      end

      def valid?
        if @page_url && @image_url && @title && @price
          true
        else
          false
        end
      end

      private

      def parse_page_url(resp_item)
        begin
          resp_item.get("DetailPageURL") 
        rescue
          nil
        end
      end

      def parse_image_url(resp_item)
        begin
          resp_item.get_hash('MediumImage')['URL']
        rescue
          nil
        end
      end

      def parse_title(resp_item)
        begin
          resp_item.get_element('ItemAttributes').get_unescaped('Title')
        rescue
          nil
        end
      end

      def parse_price(resp_item)
        begin
          resp_item.get_element('OfferSummary').get_element('LowestNewPrice').get_unescaped('FormattedPrice')
        rescue
          nil
        end
      end
    end
  end
end
