defmodule Cuevolution.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Cuevolution.RateLimiter

  defp unique_key, do: {:test, System.unique_integer([:positive])}

  test "allows hits up to the limit, then rejects with a retry-after" do
    key = unique_key()

    for _ <- 1..3, do: assert(:ok = RateLimiter.hit(key, 3, :timer.minutes(10)))

    assert {:error, :rate_limited, retry_after_ms} = RateLimiter.hit(key, 3, :timer.minutes(10))
    assert retry_after_ms > 0 and retry_after_ms <= :timer.minutes(10)
  end

  test "keys are limited independently" do
    a = unique_key()
    b = unique_key()

    assert :ok = RateLimiter.hit(a, 1, :timer.minutes(10))
    assert {:error, :rate_limited, _} = RateLimiter.hit(a, 1, :timer.minutes(10))
    assert :ok = RateLimiter.hit(b, 1, :timer.minutes(10))
  end

  test "the counter resets once the window rolls over" do
    key = unique_key()

    assert :ok = RateLimiter.hit(key, 1, 50)
    assert {:error, :rate_limited, _} = RateLimiter.hit(key, 1, 50)

    Process.sleep(60)

    assert :ok = RateLimiter.hit(key, 1, 50)
  end
end
