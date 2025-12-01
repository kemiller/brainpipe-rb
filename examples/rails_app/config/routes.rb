Rails.application.routes.draw do
  mount Brainpipe::Rails::Engine => "/brainpipe"
end
