defmodule MnemosyneEcto.SqliteVec.Float32 do
  @moduledoc """
  A float32 vector in the little-endian blob format used by `sqlite-vec`.
  """

  defstruct [:data]

  @type t :: %__MODULE__{data: binary()}

  @doc "Builds a vector from a list of numbers, or returns an existing vector."
  @spec new(t() | [number()]) :: t()
  def new(%__MODULE__{} = vector), do: vector

  def new(list) when is_list(list) do
    from_binary(for v <- list, into: <<>>, do: <<v::float-32-little>>)
  end

  @doc "Wraps a little-endian float32 blob."
  @spec from_binary(binary()) :: t()
  def from_binary(binary) when is_binary(binary), do: %__MODULE__{data: binary}

  @doc "Returns the little-endian float32 blob."
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{data: data}), do: data

  @doc "Converts the vector to a list of floats."
  @spec to_list(t()) :: [float()]
  def to_list(%__MODULE__{data: data}), do: for(<<v::float-32-little <- data>>, do: v)
end

defmodule MnemosyneEcto.SqliteVec.Ecto.Float32 do
  @moduledoc """
  `Ecto.Type` storing `MnemosyneEcto.SqliteVec.Float32` as a binary blob.
  """
  use Ecto.Type

  alias MnemosyneEcto.SqliteVec.Float32

  @impl true
  def type, do: :binary

  @impl true
  def cast(value), do: {:ok, Float32.new(value)}

  @impl true
  def load(data), do: {:ok, Float32.from_binary(data)}

  @impl true
  def dump(%Float32{} = vector), do: {:ok, Float32.to_binary(vector)}
  def dump(_), do: :error
end
