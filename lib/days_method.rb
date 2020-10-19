# frozen_string_literal: true

# helper class to convert number into days
# this avoids adding rails activesupport just
# to easily compute the expiry date in tenant_api
class Integer
  def days
    self * 86_400
  end
end
