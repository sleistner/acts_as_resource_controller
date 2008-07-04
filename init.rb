require 'acts_as_resource_controller'

if defined?(ActionController) and defined?(ActionController::Base)
  ActionController::Base.send :include, ActsAsResourceController
end
