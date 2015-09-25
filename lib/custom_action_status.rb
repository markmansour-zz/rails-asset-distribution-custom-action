class CustomActionStatus
  attr_reader :error, :message

  def initialize(is_ok, error = nil, message = nil, expected = true)
    @is_ok = is_ok
    @error = error
    @message = message
    @expected = expected
  end

  def ok?
    @is_ok
  end

  def error?
    ! ok?
  end

  def expected?
    @expected
  end

  def to_h
    if ok?
      { status: "ok" }
    else
      { status: "error", message: @message }
    end
  end
end
