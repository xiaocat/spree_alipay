module Spree
  class AlipayController < StoreController
    ssl_allowed
    skip_before_filter :verify_authenticity_token

    def alipay_timestamp # :nodoc: all
      Timeout::timeout(10){ HTTParty.get(alipay_url('service' => 'query_timestamp')) }['alipay']['response']['timestamp']['encrypt_key']
    end

    def alipay_url(options) # :nodoc: all
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

    def checkout
      order = current_order || raise(ActiveRecord::RecordNotFound)

      options = {
        'subject' => "#{order.line_items[0].product.name}等#{order.line_items.count}件",
        'body' => "#{order.number}",
        'out_trade_no' => order.number,
        'service' => 'create_direct_pay_by_user',
        'total_fee' => order.total,
        'show_url' => request.url.sub(request.fullpath, '') + '/products/' + order.products[0].slug,
        'return_url' => request.url.sub(request.fullpath, '') + '/alipay/notify?id=' + order.id.to_s + '&payment_method_id=' + params[:payment_method_id].to_s,
        'notify_url' => request.url.sub(request.fullpath, '') + '/alipay/notify?source=notify&id=' + order.id.to_s + '&payment_method_id=' + params[:payment_method_id].to_s,
        'payment_type' => '1',
        'anti_phishing_key' => alipay_timestamp,
        'sign_id_ext' => order.user.id,
        'sign_name_ext' => order.user.email,
        'exter_invoke_ip' => request.remote_ip
      }

      url = alipay_url(options)
      # render json:  { 'url' => url , 'options' => options}
      render json:  { 'url' => url }
    end

    def notify
      order = Spree::Order.find(params[:id]) || raise(ActiveRecord::RecordNotFound)

      if order.complete?
        success_return order
        return
      end

      request_valid = Timeout::timeout(10){ HTTParty.get("https://mapi.alipay.com/gateway.do?service=notify_verify&partner=#{payment_method.preferences[:pid]}&notify_id=#{params[:notify_id]}") }

      unless request_valid && params[:total_fee] == order.total
        failure_return order
        return
      end

      # unless params['sign'].downcase == Digest::MD5.hexdigest(params.except(*%w[controller action id sign_type sign source payment_method_id]).sort.map{|k,v| "#{k}=#{CGI.unescape(v.to_s)}" }.join("&")+ payment_method.preferences[:key])
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