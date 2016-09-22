class Account < ApplicationRecord
  DEFAULT_PERMISSIONS_BITMASK = 0

  has_one :access_token, :class_name => "Doorkeeper::AccessToken", :foreign_key => :resource_owner_id
  has_many :phone_calls
  has_many :incoming_phone_numbers

  bitmask :permissions,
          :as => [
            :manage_inbound_phone_calls,
            :manage_call_data_records
          ],
          :null => false

  alias_attribute :sid, :id
  before_validation :set_default_permissions_bitmask, :on => :create

  def auth_token
    access_token && access_token.token
  end

  private

  def set_default_permissions_bitmask
    self.permissions_bitmask = DEFAULT_PERMISSIONS_BITMASK if permissions.empty?
  end
end
