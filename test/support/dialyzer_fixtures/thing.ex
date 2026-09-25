defmodule DialyzerFixtures.Thing do
  @moduledoc false

  use TypedStruct

  typedstruct do
    plugin(TypedStructBuilderValidators)

    field(:name, String.t(), enforce: true)
    field(:count, integer(), enforce: true)
    field(:note, String.t(), default: "")

    validator &(&1.count >= 0), "count must not be negative"
  end
end
