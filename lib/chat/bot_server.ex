defmodule Chat.BotServer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    schedule_work()

    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    Chat.Bot.broadcast_message()

    schedule_work()

    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, Enum.random(4..20) * 1000)
  end
end
