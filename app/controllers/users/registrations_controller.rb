class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_account_update_params, only: [ :update ]
  before_action :stash_remove_avatar_flag, only: [ :update ]

  protected

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :display_name, :avatar ])
  end

  def after_update_path_for(_resource)
    edit_user_registration_path
  end

  def update_resource(resource, params)
    result = super
    if result && @remove_avatar && params[:avatar].blank? && resource.avatar.attached?
      resource.avatar.purge
    end
    result
  end

  private

  def stash_remove_avatar_flag
    @remove_avatar = params.dig(:user, :remove_avatar) == "1"
  end
end
