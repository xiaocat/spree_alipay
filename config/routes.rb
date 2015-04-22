Spree::Core::Engine.routes.draw do
  # Add your extension routes here
  get '/alipay/checkout', :to => "alipay#checkout"
  get '/alipay/:id/checkout', :to => "alipay#checkout_api"
  post '/alipay/:id/query', :to => "alipay#query"
  post '/alipay/notify', :to => "alipay#notify"
  get '/alipay/notify', :to => "alipay#notify"
end
