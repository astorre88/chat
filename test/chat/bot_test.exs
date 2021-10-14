defmodule Chat.BotTest do
  use ExUnit.Case, async: true

  alias Chat.Bot, as: Subject
  alias Chat.Response

  setup_all do
    start_supervised({Registry, keys: :duplicate, name: Registry.Chat})
    :ok
  end

  describe "broadcast_message/0" do
    test "sends random message to registered but not to initiator" do
      connection1 =
        Task.async(fn ->
          {:ok, _} = Registry.register(Registry.Chat, "chat", {})

          receive do
            :proceed -> :ok
          end

          receive do
            :proceed -> :ok
          end

          Subject.broadcast_message()

          message =
            Jason.encode!(%Response{
              topic: "bot_room",
              event: "reply",
              status: :ok,
              payload: %{message: "test", name: "Бот", foreign: true}
            })

          refute_received ^message
        end)

      connection2 =
        Task.async(fn ->
          {:ok, _} = Registry.register(Registry.Chat, "chat", {})

          send(connection1.pid, :proceed)
          assert_receive message

          assert %{
                   "event" => "reply",
                   "payload" => %{"foreign" => true, "message" => _, "name" => "Бот"},
                   "status" => "ok",
                   "topic" => "bot_room"
                 } = Jason.decode!(message)
        end)

      connection3 =
        Task.async(fn ->
          {:ok, _} = Registry.register(Registry.Chat, "chat", {})

          send(connection1.pid, :proceed)
          assert_receive message

          assert %{
                   "event" => "reply",
                   "payload" => %{"foreign" => true, "message" => _, "name" => "Бот"},
                   "status" => "ok",
                   "topic" => "bot_room"
                 } = Jason.decode!(message)
        end)

      Enum.map([connection1, connection2, connection3], &Task.await/1)
    end

    test "does not send a message to unregistered" do
      Subject.broadcast_message()

      message =
        Jason.encode!(%Response{
          topic: "bot_room",
          event: "reply",
          status: :ok,
          payload: %{message: "test", name: "Бот", foreign: true}
        })

      refute_received ^message
    end
  end
end
