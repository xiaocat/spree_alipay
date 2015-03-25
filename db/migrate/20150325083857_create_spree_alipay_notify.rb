class CreateSpreeAlipayNotify < ActiveRecord::Migration
  def change
    create_table :spree_alipay_notifies do |t|
      t.string :out_trade_no
      t.string :trade_no
      t.string :seller_email
      t.string :buyer_email
      t.string :total_fee
      t.text   :source_data
      t.datetime :created_at
    end
  end
end
