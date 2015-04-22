module Spree
  class AlipayController < StoreController
    skip_before_filter :verify_authenticity_token

    def alipay_timestamp
      Timeout::timeout(10){ HTTParty.get(alipay_url('service' => 'query_timestamp')) }['alipay']['response']['timestamp']['encrypt_key']
    end

    def alipay_url(options)
      options.merge!({
        'seller_email' => payment_method.preferences[:email],
        'partner' => payment_method.preferences[:pid],
        '_input_charset' => 'utf-8',
      })
      options.merge!({
        'sign_type' => 'MD5',
        'sign' => Digest::MD5.hexdigest(options.sort.map{|k,v|"#{k}=#{v}"}.join("&")+payment_method.preferences[:key]),
      })
      action = "https://mapi.alipay.com/gateway.do"
      cgi_escape_action_and_options(action, options)
    end

    def cgi_escape_action_and_options(action, options) # :nodoc: all
      "#{action}?#{options.sort.map{|k, v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}" }.join('&')}"
    end

    def pay_options(order)
      return_host = payment_method.preferences[:returnHost].blank? ? request.url.sub(request.fullpath, '') : payment_method.preferences[:returnHost]
      show_url = params[:redirect_url].blank? ? (request.url.sub(request.fullpath, '') + '/products/' + order.products[0].slug) : params[:redirect_url]

      options = {
          'subject' => "#{order.line_items[0].product.name}等#{order.line_items.count}件",
          'body' => "#{order.number}",
          'out_trade_no' => order.number,
          'service' => 'create_direct_pay_by_user',
          'total_fee' => order.total,
          'show_url' => show_url,
          'return_url' => return_host + '/alipay/notify?id=' + order.id.to_s + '&payment_method_id=' + params[:payment_method_id].to_s,
          'notify_url' => return_host + '/alipay/notify?source=notify&id=' + order.id.to_s + '&payment_method_id=' + params[:payment_method_id].to_s,
          'payment_type' => '1',
          'anti_phishing_key' => alipay_timestamp,
          'sign_id_ext' => order.user.id,
          'sign_name_ext' => order.user.email,
          'exter_invoke_ip' => request.remote_ip
      }

      url = alipay_url(options)
    end

    def checkout
      order = current_order || raise(ActiveRecord::RecordNotFound)
      render json:  { 'url' => self.pay_options(order) }
    end

    def checkout_api
      order = Spree::Order.find(params[:id])  || raise(ActiveRecord::RecordNotFound)
      render json:  { 'url' => self.pay_options(order) }
    end

    def notify
      order = Spree::Order.find(params[:id]) || raise(ActiveRecord::RecordNotFound)

      if order.complete?
        success_return order
        return
      end

      request_valid = Timeout::timeout(10){ HTTParty.get("https://mapi.alipay.com/gateway.do?service=notify_verify&partner=#{payment_method.preferences[:pid]}&notify_id=#{params[:notify_id]}") }

      unless request_valid && params[:total_fee] == order.total.to_s
        failure_return order
        return
      end

      # unless params['sign'].downcase == Digest::MD5.hexdigest(params.except(*%w[id sign_type sign source payment_method_id]).sort.map{|k,v| "#{k}=#{CGI.unescape(v.to_s)}" }.join("&")+ payment_method.preferences[:key])
      #   failure_return order
      #   return
      # end

      order.payments.create!({
        :source => Spree::AlipayNotify.create({
            :out_trade_no => params[:out_trade_no],
            :trade_no => params[:trade_no],
            :seller_email => params[:seller_email],
            :buyer_email => params[:buyer_email],
            :total_fee => params[:total_fee],
            :source_data => params.to_json
        }),
        :amount => order.total,
        :payment_method => payment_method
      })

      order.next
      if order.complete?
        success_return order
      else
        failure_return order
      end
    end

    def query
      order = Spree::Order.find(params[:id]) || raise(ActiveRecord::RecordNotFound)

      if order.complete?
        render json: { 'errCode' => 0, 'msg' => 'success'}
        return
      end

      r = begin
        Timeout::timeout(10) do
          r = HTTParty.get(alipay_url('out_trade_no' => order.number, 'service' => 'single_trade_query'))
          Rails.logger.info "alipay_query #{r.inspect}"
          r
        end
      rescue Exception => e
        Rails.logger.info "alipay_query_exception #{r.inspect}"
        false
      end

      if r && r['alipay'] && r['alipay']['response'] && r['alipay']['response']['trade'] && %w[TRADE_FINISHED TRADE_SUCCESS].include?(r['alipay']['response']['trade']['trade_status']) && r['alipay']['is_success'] == 'T' && r['alipay']['sign'] == Digest::MD5.hexdigest(r['alipay']['response']['trade'].sort.map{|k,v|"#{k}=#{v}"}.join("&") + payment_method.preferences[:key])
        order.payments.create!({
          :source => Spree::AlipayNotify.create({
            :out_trade_no => r['alipay']['response']['trade']['out_trade_no'],
            :trade_no => r['alipay']['response']['trade']['trade_no'],
            :seller_email => r['alipay']['response']['trade']['seller_email'],
            :buyer_email => r['alipay']['response']['trade']['buyer_email'],
            :total_fee => r['alipay']['response']['trade']['total_fee'],
            :source_data => r['alipay']['response']['trade'].to_json
          }),
          :amount => order.total,
          :payment_method => payment_method
        })
        order.next
        if order.complete?
          render json: { 'errCode' => 0, 'msg' => 'success'}
        else
          render json: { 'errCode' => 1, 'msg' => 'failure'}
        end
      else
        render json: { 'errCode' => 1, 'msg' => 'failure'}
      end
    end

    def success_return(order)
      if params[:source] == 'notify'
        render :text => "success", :layout => false
      else
        redirect_to "/orders/#{order.number}"
      end
    end

    def failure_return(order)
      if params[:source] == 'notify'
        render :text => "failure", :layout => false
      else
        redirect_to "/orders/#{order.number}"
      end
    end

    def payment_method
      Spree::PaymentMethod.find(params[:payment_method_id])
    end
  end
end