# frozen_string_literal: true

# Error class wrapper for rest-client errors
class ErrorResponse
  def initialize(error_msg, code)
    @body = error_msg
    @code = code
  end

  attr_reader :code
  attr_reader :body
end

# Helper class to log to stdout
class StdOutLogger
  def info(msg)
    puts msg
  end

  def debug(_msg)
    # puts _msg
  end

  def error(msg)
    puts msg
  end

  def warning(msg)
    puts msg
  end
end

# helper class to convert number into days
# this avoids adding rails activesupport just
# to easily compute the expiry date in tenant_api
class Integer
  def days
    self * 86_400
  end
end
