defmodule Chat.WSHandlerTest do
  use ExUnit.Case, async: true

  alias Chat.WSHandler, as: Subject
  alias Chat.Response

  @moduletag capture_log: true

  setup_all do
    start_supervised({Horde.Registry, keys: :duplicate, name: Registry.Chat})
    :ok
  end

  describe "websocket_init/1" do
    test "correctly inits a state" do
      assert %{room_name: "room1" = room_name} = initial_state = struct(Subject)

      assert {:reply, {:text, message},
              %Chat.WSHandler{room_name: ^room_name, user_name: user_name}} =
               Subject.websocket_init(initial_state)

      assert %{
               "topic" => ^room_name,
               "event" => "join",
               "status" => "ok",
               "payload" => %{"rooms" => [^room_name], "user_name" => ^user_name}
             } = Jason.decode!(message)
    end

    test "sets a user_name with PID" do
      assert %{user_name: nil} = initial_state = struct(Subject)

      {:reply, {:text, _}, %Chat.WSHandler{user_name: user_name}} =
        Subject.websocket_init(initial_state)

      [[pid_str]] = Regex.scan(~r/[\d\.]+/, user_name)

      assert is_pid(:erlang.list_to_pid('<#{pid_str}>'))
    end

    test "registers a connection" do
      self_pid = self()
      self_pid_str = inspect(self_pid)

      assert {:reply, {:text, _}, %Chat.WSHandler{user_name: ^self_pid_str}} =
               Subject.websocket_init(struct(Subject))

      assert [{"room1", ^self_pid}] =
               Horde.Registry.select(Registry.Chat, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    end
  end

  describe "websocket_handle/2" do
    setup do
      %{state: %Subject{user_name: "user"}}
    end

    test "handles browser PING message", %{state: state} do
      assert {:reply, {:pong, "PONG"}, %{room_name: "room1", user_name: "user"}} =
               Subject.websocket_handle({:ping, "PING"}, state)
    end

    test "handles client heartbeat message", %{state: state} do
      assert {:reply, {:text, message}, %{room_name: "room1", user_name: "user"}} =
               Subject.websocket_handle({:text, "ping"}, state)

      assert %{"event" => "heartbeat", "payload" => %{}, "status" => "ok", "topic" => "system"} =
               Jason.decode!(message)
    end

    test "does not handle uncodable message", %{state: state} do
      assert_raise Jason.DecodeError, "unexpected byte at position 0: 0x61 ('a')", fn ->
        Subject.websocket_handle({:text, "abc"}, state)
      end
    end

    test "handles proper message with a key 'message'", %{state: state} do
      request_message = Jason.encode!(%{data: %{message: "Hello!"}})

      assert {:reply, {:text, message}, %Chat.WSHandler{room_name: "room1", user_name: "user"}} =
               Subject.websocket_handle({:text, request_message}, state)

      assert %{
               "topic" => "room1",
               "event" => "reply",
               "status" => "ok",
               "payload" => %{"foreign" => false, "message" => "Hello!"}
             } = Jason.decode!(message)
    end

    test "sends a message to selected room but not to initiator", %{state: state} do
      full_state = %{state | user_name: "user"}
      request_message = Jason.encode!(%{data: %{message: "Hello!"}})

      room_connection1 =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "room1", {})

          receive do
            :proceed -> :ok
          end

          receive do
            :proceed -> :ok
          end

          Subject.websocket_handle({:text, request_message}, full_state)

          message =
            Jason.encode!(%Response{
              topic: "room1",
              event: "reply",
              status: :ok,
              payload: %{
                message: "Hello!",
                name: "user",
                foreign: true
              }
            })

          refute_received ^message
        end)

      foreign_connection =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "chat", {})

          send(room_connection1.pid, :proceed)

          message =
            Jason.encode!(%Response{
              topic: "room1",
              event: "reply",
              status: :ok,
              payload: %{
                message: "Hello!",
                name: "user",
                foreign: true
              }
            })

          refute_received ^message
        end)

      room_connection2 =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "room1", {})

          send(room_connection1.pid, :proceed)
          assert_receive message

          assert %{
                   "event" => "reply",
                   "payload" => %{"foreign" => true, "message" => "Hello!", "name" => "user"},
                   "status" => "ok",
                   "topic" => "room1"
                 } = Jason.decode!(message)
        end)

      Enum.map([room_connection1, foreign_connection, room_connection2], &Task.await/1)
    end

    test "changes room with a key 'change_room'", %{state: state} do
      request_message = Jason.encode!(%{data: %{change_room: "Chat"}})

      assert {:reply, {:text, message}, %Chat.WSHandler{room_name: "Chat", user_name: "user"}} =
               Subject.websocket_handle({:text, request_message}, state)

      assert %{
               "topic" => "Chat",
               "event" => "join",
               "status" => "ok",
               "payload" => %{"rooms" => ["Chat"], "user_name" => "user"}
             } = Jason.decode!(message)
    end

    test "moves from the room to a new one with a key 'change_room'", %{state: state} do
      self_pid = self()
      request_message = Jason.encode!(%{data: %{change_room: "Chat"}})

      Subject.websocket_init(state)

      assert [{"room1", ^self_pid}] =
               Horde.Registry.select(Registry.Chat, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])

      Subject.websocket_handle({:text, request_message}, state)

      assert [{"Chat", ^self_pid}] =
               Horde.Registry.select(Registry.Chat, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    end

    test "notifies everyone with a new room except initiator", %{state: state} do
      request_message = Jason.encode!(%{data: %{change_room: "Chat"}})

      room_connection1 =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "room1", {})

          receive do
            :proceed -> :ok
          end

          receive do
            :proceed -> :ok
          end

          Subject.websocket_handle({:text, request_message}, state)

          message =
            Jason.encode!(%Response{
              topic: "Chat",
              event: "set_room",
              status: :ok,
              payload: %{
                rooms: ["abc", "Chat"]
              }
            })

          refute_received ^message
        end)

      room_connection2 =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "Chat", {})

          send(room_connection1.pid, :proceed)

          assert_receive message

          assert %{
                   "event" => "set_room",
                   "payload" => %{"rooms" => ["Chat", "abc"]},
                   "status" => "ok",
                   "topic" => "Chat"
                 } = Jason.decode!(message)
        end)

      foreign_connection =
        Task.async(fn ->
          {:ok, _} = Horde.Registry.register(Registry.Chat, "abc", {})

          send(room_connection1.pid, :proceed)
          assert_receive message

          assert %{
                   "event" => "set_room",
                   "payload" => %{"rooms" => ["Chat", "abc"]},
                   "status" => "ok",
                   "topic" => "Chat"
                 } = Jason.decode!(message)
        end)

      Enum.map([room_connection1, room_connection2, foreign_connection], &Task.await/1)
    end

    test "changes name with a key 'set_name'", %{state: state} do
      request_message = Jason.encode!(%{data: %{set_name: "John Doe"}})

      assert {:reply, {:text, message},
              %Chat.WSHandler{room_name: "room1", user_name: "John Doe"}} =
               Subject.websocket_handle({:text, request_message}, state)

      assert %{
               "topic" => "room1",
               "event" => "set_name",
               "status" => "ok",
               "payload" => %{"user_name" => "John Doe"}
             } = Jason.decode!(message)
    end

    test "returns unmatched proper message as is", %{state: state} do
      request_message = Jason.encode!(%{data: %{undefined: "undefined"}})

      assert {:reply, {:text, message}, %Chat.WSHandler{room_name: "room1", user_name: "user"}} =
               Subject.websocket_handle({:text, request_message}, state)

      assert message == %{"data" => %{"undefined" => "undefined"}}
    end
  end
end
