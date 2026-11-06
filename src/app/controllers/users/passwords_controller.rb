class Users::PasswordsController < Devise::PasswordsController
  include SensitiveTokenResponse
end
