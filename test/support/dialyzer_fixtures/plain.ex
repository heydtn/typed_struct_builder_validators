defmodule DialyzerFixtures.Plain do
  @moduledoc false

  # No validators, so `validate/1` can only answer `:ok`. Kept as a fixture of
  # its own because that is the shape most likely to draw a warning about an
  # unreachable error branch in the generated code.

  use TypedStruct

  typedstruct do
    plugin(TypedStructBuilderValidators)

    field(:name, String.t(), enforce: true)
    field(:note, String.t(), default: "")
  end
end

defmodule DialyzerFixtures.PlainUse do
  @moduledoc false

  alias DialyzerFixtures.Plain

  @spec build() :: {:ok, Plain.t()} | {:error, [String.t()]}
  def build, do: Plain.new(%{name: "a"})

  @spec build!() :: Plain.t()
  def build!, do: Plain.new!(%{name: "a", note: "n"})

  @spec replace(Plain.t()) :: {:ok, Plain.t()} | {:error, [String.t()]}
  def replace(plain), do: Plain.put(plain, %{note: "n"})

  @spec change(Plain.t()) :: {:ok, Plain.t()} | {:error, [String.t()]}
  def change(plain), do: Plain.update(plain, %{note: &String.upcase/1})

  # With no validators declared, validate/1 is typed as answering only :ok.
  @spec check(Plain.t()) :: :ok
  def check(plain), do: Plain.validate(plain)

  @spec read(Plain.t()) :: String.t()
  def read(plain), do: Plain.put!(plain, %{note: "n"}).note
end
