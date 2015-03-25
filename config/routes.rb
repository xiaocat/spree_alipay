Spree::Core::Engine.routes.draw do
  # Add your extension routes here
  get '/alipay/checkout', :to => "alipay#checkout"
  post '/alipay/notify', :to => "alipay#notify"
  get '/alipay/notify', :to => "alipay#notify"
end
