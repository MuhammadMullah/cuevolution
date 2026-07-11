defmodule Cuevolution.Accounts.PhoneNumber do
  @moduledoc """
  Normalizes mobile numbers to E.164 via `ex_phone_number` (a libphonenumber
  port), defaulting to Kenya (`"KE"`) when no region is given (FR-013).
  """

  @default_region "KE"

  @spec normalize(String.t() | nil, String.t() | nil) :: {:ok, String.t()} | :error
  def normalize(raw, region_code \\ @default_region)

  def normalize(nil, _region_code), do: :error

  def normalize(raw, region_code) when is_binary(raw) do
    region = region_code || @default_region

    with {:ok, phone_number} <- ExPhoneNumber.parse(raw, region),
         true <- ExPhoneNumber.is_valid_number?(phone_number) do
      {:ok, ExPhoneNumber.format(phone_number, :e164)}
    else
      _ -> :error
    end
  end
end
