defmodule Chat.WSHandler do
  @behaviour :cowboy_websocket

  alias Chat.Response

  require Logger

  defstruct [:user_name, room_name: "room1"]

  def init(req, _) do
    state = struct(__MODULE__)
    Logger.info("get connection to #{state.room_name}...")

    {:cowboy_websocket, req, state}
  end

  def websocket_init(%{room_name: room_name} = state) do
    Logger.info("registering #{inspect(self())}...")
    register(room_name)

    user_name = inspect(self())

    {:reply,
     {:text,
      Jason.encode!(%Response{
        topic: room_name,
        event: "join",
        status: :ok,
        payload: %{user_name: user_name, rooms: rooms()}
      })}, %{state | user_name: user_name}}
  end

  def websocket_handle({:ping, "PING"}, state) do
    Logger.info("received browser PING from #{inspect(self())}, state: #{inspect(state)}")
    {:reply, {:pong, "PONG"}, state}
  end

  def websocket_handle({:text, "ping"}, state) do
    {:reply, {:text, Jason.encode!(%Response{topic: "system", event: "heartbeat", status: :ok})},
     state}
  end

  def websocket_handle({:text, json}, %{room_name: room_name, user_name: user_name} = state) do
    Logger.info(
      "received message #{inspect(json)} from #{inspect(self())}, state: #{inspect(state)}"
    )

    json |> Jason.decode!() |> handle_message(state)
  end

  def websocket_handle(frame, state) do
    Logger.warn(
      "received unmatched message #{inspect(frame)} from #{inspect(self())}, state: #{
        inspect(state)
      }"
    )

    {:ok, state}
  end

  def websocket_info(info, state) do
    Logger.info("websocket_info: #{inspect(info)}")

    {:reply, {:text, info}, state}
  end

  def terminate(reason, _req, state) do
    Logger.info(
      "#{inspect(self())}disconnected, reason: #{inspect(reason)}, state: #{inspect(state)}"
    )

    :ok
  end

  defp handle_message(
         %{"data" => %{"message" => message}},
         %{room_name: room_name, user_name: user_name} = state
       ) do
    current_pid = self()

    Registry.dispatch(Registry.Chat, room_name, fn entries ->
      for {pid, _} <- entries do
        if pid != current_pid do
          Process.send(
            pid,
            Jason.encode!(%Response{
              topic: room_name,
              event: "reply",
              status: :ok,
              payload: %{
                message: message,
                name: user_name,
                foreign: true
              }
            }),
            []
          )
        end
      end
    end)

    {:reply,
     {:text,
      Jason.encode!(%Response{
        topic: room_name,
        event: "reply",
        status: :ok,
        payload: %{message: message, foreign: false}
      })}, state}
  end

  defp handle_message(
         %{"data" => %{"change_room" => new_room_name}},
         %{room_name: room_name, user_name: user_name} = state
       ) do
    Registry.unregister_match(Registry.Chat, room_name, {})
    register(new_room_name)

    {:reply,
     {:text,
      Jason.encode!(%Response{
        topic: new_room_name,
        event: "join",
        status: :ok,
        payload: %{user_name: user_name, rooms: rooms()}
      })}, %{state | room_name: new_room_name}}
  end

  defp handle_message(
         %{"data" => %{"set_name" => new_user_name}},
         %{room_name: room_name, user_name: old_user_name} = state
       ) do
    user_name = new_user_name || old_user_name

    {:reply,
     {:text,
      Jason.encode!(%Response{
        topic: room_name,
        event: "set_name",
        status: :ok,
        payload: %{user_name: user_name}
      })}, %{state | user_name: user_name}}
  end

  defp handle_message(message, state) do
    {:reply, {:text, message}, state}
  end

  defp rooms() do
    Registry.Chat |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}]) |> Enum.uniq()
  end

  defp register(room_name) do
    Registry.register(Registry.Chat, room_name, {})
    current_pid = self()
    rooms_list = rooms()

    for pid <- Registry.select(Registry.Chat, [{{:_, :"$2", :_}, [], [:"$2"]}]) do
      if pid != current_pid do
        Process.send(
          pid,
          Jason.encode!(%Response{
            topic: room_name,
            event: "set_room",
            status: :ok,
            payload: %{rooms: rooms_list}
          }),
          []
        )
      end
    end
  end
end
