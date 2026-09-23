# frozen_string_literal: true

Rails.application.routes.draw do
  get "answer", to: "requests#answer"
  match "fail", to: "requests#failure", via: [ :get, :post ]
end
