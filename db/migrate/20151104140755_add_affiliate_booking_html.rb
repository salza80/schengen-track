class AddAffiliateBookingHtml < ActiveRecord::Migration[5.1]
  def change
    add_column :countries, :affiliate_booking_html, :text
  end
end
