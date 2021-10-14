defmodule Chat.Response do
  @derive {Jason.Encoder, only: [:topic, :event, :status, :payload]}
  @enforce_keys [:topic, :event, :status]
  defstruct [:topic, :event, :status, payload: %{}]
end
