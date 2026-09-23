# frozen_string_literal: true

Rails.application.routes.draw do
  match "fail", to: "requests#failure", via: [ :get, :post ]
end
