defmodule Chat.Bot do
  alias Chat.Response

  @anecdotes [
    "Население, стиравшее пакеты, трудно убедить в том, что маска - одноразовая.",
    "Если бы я был булкой, меня бы звали круассавчиком.",
    "Учитесь у мяча: чем сильнее его бьют, тем выше он взлетает.",
    "- Деньги - цветы жизни! - Может, дети? - Нет.",
    "- Бэрримор, а что конец света уже наступил? - Нет, сэр, еще репетируют.",
    "Мясники в России настолько крутые, что у них есть свой доктор!",
    "Хороша машина, только в пробке паршиво.",
    "Как вообще понять, что волынщик играет хорошо?"
  ]

  def broadcast_message do
    encoded =
      Jason.encode!(%Response{
        topic: "bot_room",
        event: "reply",
        status: :ok,
        payload: %{message: Enum.random(@anecdotes), name: "Бот", foreign: true}
      })

    for pid <- Registry.select(Registry.Chat, [{{:_, :"$2", :_}, [], [:"$2"]}]) do
      Process.send(pid, encoded, [])
    end
  end
end
