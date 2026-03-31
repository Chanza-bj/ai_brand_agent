defmodule AiBrandAgent.Config.Env do
  @moduledoc """
  Environment lookup with optional **`brand_` / `BRAND_` prefixes** so this app can share a
  host with other Phoenix apps without colliding on generic names like `PORT` or `PHX_SERVER`.

  Resolution order for a logical key `KEY`:

  1. `brand_KEY` (e.g. `brand_PORT`, `brand_PHX_SERVER`)
  2. `BRAND_KEY` (e.g. `BRAND_PORT`)
  3. `KEY` (standard Phoenix / library convention)

  Use in `config/runtime.exs` only.
  """

  @doc """
  First non-empty string from `brand_<key>`, `BRAND_<KEY>`, or `<key>`; otherwise `nil`.
  """
  def get(key) when is_binary(key) do
    prefixed = "brand_" <> key
    upper = "BRAND_" <> String.upcase(key)

    first_non_empty([
      System.get_env(prefixed),
      System.get_env(upper),
      System.get_env(key)
    ])
  end

  defp first_non_empty([h | t]) do
    cond do
      is_binary(h) and String.trim(h) != "" -> String.trim(h)
      true -> first_non_empty(t)
    end
  end

  defp first_non_empty([]), do: nil

  @doc """
  Like `get/1` but raises if unset or blank.
  """
  def get!(key) when is_binary(key) do
    case get(key) do
      nil ->
        raise """
        environment variable #{key} is missing (set #{key}, brand_#{key}, or BRAND_#{String.upcase(key)})
        """

      v ->
        v
    end
  end
end
