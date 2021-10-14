(() => {
  const otherMessage =
    '<div class="chat-message"><div class="flex items-end justify-end"><div class="flex flex-col space-y-2 text-xs max-w-xs mx-2 order-1 items-end"><div><span class="px-4 py-2 rounded-lg inline-block rounded-br-none bg-blue-600 text-white">';
  const myMessage =
    '<div class="flex items-end"><div class="flex flex-col space-y-2 text-xs max-w-xs mx-2 order-2 items-start"><div><span class="px-4 py-2 rounded-lg inline-block bg-gray-300 text-gray-600">';

  class myWebsocketHandler {
    constructor(room) {
      this.room = room;
      this.user = null;
    }

    setupSocket(roomURL, tries = 1) {
      this.socket = new WebSocket(roomURL);

      this.socket.onopen = () => {
        this.socket.send(
          JSON.stringify({
            data: {
              change_room: this.room,
            },
          })
        );
        this.socket.send(
          JSON.stringify({
            data: {
              set_name: this.user,
            },
          })
        );
      };

      this.socket.onmessage = event => {
        const parsedResponse = JSON.parse(event.data);

        if (parsedResponse.topic !== "system") {
          switch (parsedResponse.event) {
            case "join":
              this.room = parsedResponse.topic;
              document.getElementById("room-label").innerHTML =
                parsedResponse.topic;
              this.user = parsedResponse.payload.user_name;
              document.getElementById("user-label").innerHTML =
                parsedResponse.payload.user_name;
              this.updateRooms(parsedResponse.payload.rooms);
              document.getElementById("messages").innerHTML = "";
              break;
            case "set_room":
              this.updateRooms(parsedResponse.payload.rooms);
              break;
            case "set_name":
              this.user = parsedResponse.payload.user_name;
              document.getElementById("user-label").innerHTML =
                parsedResponse.payload.user_name;
              break;
            default:
              const pTag = document.createElement("div");
              pTag.classList.add("chat-message");
              pTag.innerHTML = `${
                parsedResponse.payload.foreign ? otherMessage : myMessage
              }${
                parsedResponse.payload.message
              }</span></div></div><span class="order-1">${
                parsedResponse.payload.foreign
                  ? parsedResponse.payload.name
                  : "Вы"
              }</span></div>`;

              const messagesBlock = document.getElementById("messages");
              messagesBlock.append(pTag);
              messagesBlock.scrollTop = messagesBlock.scrollHeight;
          }
        }
      };

      this.socket.onclose = event => {
        if (event.wasClean) {
          console.log(
            `[close] Connection clearly closed, code = ${event.code}, reason = ${event.reason}`
          );
        } else {
          console.log(
            `[close] Connection closed, code = ${event.code}, reason = ${event.reason}`
          );
        }
        setTimeout(() => {
          this.setupSocket(roomURL, (tries += 1));
        }, this.reconnectAfterMs(tries));
      };
    }

    reconnectAfterMs(tries) {
      return [10, 50, 100, 150, 200, 250, 500, 1000, 2000][tries - 1] || 5000;
    }

    roomItem(roomName) {
      return `<li class="mr-6"><a class="room-link text-blue-500 hover:text-blue-800" href="#">${roomName}</a></li>`;
    }

    updateRooms(rooms) {
      const roomList = document.getElementById("rooms");
      roomList.innerHTML = rooms.map(this.roomItem).join("");
      const links = document.querySelectorAll(".room-link");
      for (const link of links) {
        link.onclick = () => this.sendChangeRoomCommand(link.textContent);
      }
    }

    changeRoom(event) {
      event.preventDefault();
      const input = document.getElementById("room-name");
      const roomName = input.value;
      input.value = "";
      const changeRoomButton = document.getElementById("create-room");
      changeRoomButton.disabled = true;
      changeRoomButton.classList.add("opacity-50", "cursor-not-allowed");
      document.getElementById("message").focus();
      this.sendChangeRoomCommand(roomName);
    }

    sendChangeRoomCommand(roomName) {
      document.getElementById("message").focus();
      this.socket.send(
        JSON.stringify({
          data: {
            change_room: roomName,
          },
        })
      );
    }

    setName(event) {
      event.preventDefault();
      const input = document.getElementById("user-name");
      const userName = input.value;
      input.value = "";
      const setNameButton = document.getElementById("set-name");
      setNameButton.disabled = true;
      setNameButton.classList.add("opacity-50", "cursor-not-allowed");
      document.getElementById("message").focus();

      this.socket.send(
        JSON.stringify({
          data: {
            set_name: userName,
          },
        })
      );
    }

    sendMessage(event) {
      event.preventDefault();
      const input = document.getElementById("message");
      const message = input.value;
      input.value = "";
      const sendMessageButton = document.getElementById("send-message");
      sendMessageButton.disabled = true;
      sendMessageButton.classList.add("opacity-50", "cursor-not-allowed");
      input.focus();

      this.socket.send(
        JSON.stringify({
          data: {
            message: message,
          },
        })
      );
    }

    slugify(text) {
      return text
        .toString()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .trim()
        .replace(/\s+/g, "-")
        .replace(/[^\w-]+/g, "")
        .replace(/--+/g, "-");
    }
  }

  function checkInput() {
    const sendButton = this.nextSibling.nextSibling;

    if (this.value.length > 0) {
      sendButton.disabled = false;
      sendButton.classList.remove("opacity-50", "cursor-not-allowed");
    } else {
      sendButton.disabled = true;
      sendButton.classList.add("opacity-50", "cursor-not-allowed");
    }
  }

  function checkMessageInput() {
    const sendMessageButton = document.getElementById("send-message");

    if (this.value.length > 0) {
      sendMessageButton.disabled = false;
      sendMessageButton.classList.remove("opacity-50", "cursor-not-allowed");
    } else {
      sendMessageButton.disabled = true;
      sendMessageButton.classList.add("opacity-50", "cursor-not-allowed");
    }
  }

  function submitOnEnter(event) {
    if (event.keyCode == 13) {
      websocketClass.sendMessage(event);
    }
  }

  const defaultRoomURL = "ws://localhost:4000/ws/chat";
  const websocketClass = new myWebsocketHandler("chat");
  websocketClass.setupSocket(defaultRoomURL);

  setInterval(() => websocketClass.socket.send("ping"), 30000);

  const changeRoomButton = document.getElementById("create-room");
  changeRoomButton.disabled = true;
  changeRoomButton.classList.add("opacity-50", "cursor-not-allowed");
  changeRoomButton.addEventListener("click", event =>
    websocketClass.changeRoom(event)
  );

  const setNameButton = document.getElementById("set-name");
  setNameButton.disabled = true;
  setNameButton.classList.add("opacity-50", "cursor-not-allowed");
  setNameButton.addEventListener("click", event =>
    websocketClass.setName(event)
  );

  const sendMessageButton = document.getElementById("send-message");
  sendMessageButton.disabled = true;
  sendMessageButton.classList.add("opacity-50", "cursor-not-allowed");
  sendMessageButton.addEventListener("click", event =>
    websocketClass.sendMessage(event)
  );

  document.getElementById("room-name").addEventListener("keyup", checkInput);
  document.getElementById("user-name").addEventListener("keyup", checkInput);
  const messageInput = document.getElementById("message");
  messageInput.addEventListener("keyup", checkMessageInput);
  messageInput.addEventListener("keyup", submitOnEnter);
  document.getElementById("message").focus();
})();
