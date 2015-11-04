class AddAffiliateBookingHtml < ActiveRecord::Migration
  def change
    add_column :countries, :affiliate_booking_html, :text
  end
end
