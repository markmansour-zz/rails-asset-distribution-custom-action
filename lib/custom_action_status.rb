class CustomActionStatus
  def initialize(is_ok, message = nil, expected = true)
    @is_ok = is_ok
    @message = message
    @expected = expected
  end

  def ok?
    is_ok
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
