defmodule UcxChat.MessageService do
  import Ecto.Query

  alias UcxChat.{
    Message, Repo, TypingAgent, User, Mention, Subscription, AppConfig,
    Settings, MessageView, ChatDat, Channel, ChannelService, UserChannel,
    SubscriptionService
  }
  alias UcxChat.ServiceHelpers, as: Helpers

  require UcxChat.ChatConstants, as: CC
  require Logger

  # def broadcast_message(id, channel_id, user_id, html) do
  #   channel = Helpers.get
  # end
  def broadcast_system_message(channel_id, _user_id, body) do
    channel = Helpers.get(Channel, channel_id)
    message = create_system_message(channel_id, body)
    html = render_message message
    resp = create_broadcast_message(message.id, channel.name, html)
    UcxChat.Endpoint.broadcast! CC.chan_room <> channel.name, "message:new", resp
  end

  def broadcast_message(id, room, user_id, html, event \\ "new")
  def broadcast_message(id, room, user_id, html, event) when is_binary(room) do
    UcxChat.Endpoint.broadcast! CC.chan_room <> room, "message:" <> event, create_broadcast_message(id, user_id, html)
  end

  def broadcast_message(socket, id, user_id, html, event) do
    Phoenix.Channel.broadcast! socket, "message:" <> event, create_broadcast_message(id, user_id, html)
  end

  def push_message(socket, id, user_id, html) do
    Phoenix.Channel.push socket, "message:new", create_broadcast_message(id, user_id, html)
  end

  defp create_broadcast_message(id, user_id, html) do
    %{
      html: html,
      id: "message-#{id}",
      user_id: user_id
    }
  end

  def get_surrounding_messages(channel_id, "", user) do
    get_messages channel_id, user
  end
  def get_surrounding_messages(channel_id, timestamp, %{tz_offset: tz}) do
    message = Repo.one from m in Message,
      where: m.timestamp == ^timestamp and m.channel_id == ^channel_id,
      preload: [:user, :edited_by]

    before_q = from m in Message,
      where: m.inserted_at < ^(message.inserted_at) and m.channel_id == ^channel_id,
      order_by: [desc: :inserted_at],
      limit: 50,
      preload: [:user, :edited_by]
    after_q = from m in Message,
      where: m.inserted_at > ^(message.inserted_at) and m.channel_id == ^channel_id,
      limit: 50,
      preload: [:user, :edited_by]

    Enum.reverse(Repo.all(before_q)) ++ [message|Repo.all(after_q)]
    |> new_days(tz || 0, [])
  end

  def get_messages(channel_id, %{tz_offset: tz}) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> Helpers.last_page
    |> preload([:user, :edited_by])
    |> Repo.all
    |> new_days(tz || 0, [])
  end

  def get_room_messages(channel_id, %{id: user_id} = user) do
    page_size = AppConfig.page_size()
    case SubscriptionService.get(channel_id, user_id) do
      %{current_message: ""} -> nil
      %{current_message: cm} ->
        cnt1 = Repo.one from m in Message,
          where: m.channel_id == ^channel_id and m.timestamp >= ^cm,
          select: count(m.id)
        if cnt1 > page_size, do: cm, else: nil
      _ -> nil
    end
    |> case do
      nil ->
        get_messages(channel_id, user)
      ts ->
        get_messsages_ge_ts(channel_id, user, ts)
    end
  end

  def get_messsages_ge_ts(channel_id, %{tz_offset: tz}, ts) do
    before_q = from m in Message,
      where: m.timestamp < ^ts,
      order_by: [desc: :inserted_at],
      limit: 25,
      preload: [:user, :edited_by]

    after_q = from m in Message,
      where: m.channel_id == ^channel_id and m.timestamp >= ^ts,
      preload: [:user, :edited_by]

    Enum.reverse(Repo.all before_q) ++ Repo.all(after_q)
    |> new_days(tz || 0, [])
  end

  def get_messages_info(messages, channel_id) do
    has_more =
      with [first|_] <- messages,
           _ <- Logger.warn("get_messages_info 2"),
           first_msg when not is_nil(first_msg) <- first_message(channel_id) do
        first.id != first_msg.id
      else
        _res -> false
      end
      has_more_next =
        with last when not is_nil(last) <- List.last(messages),
             last_msg when not is_nil(last_msg) <- last_message(channel_id) do
          last.id != last_msg.id
        else
          _res -> true
        end
    %{
      has_more: has_more, has_more_next: has_more_next, can_preview: true
    }
  end

  def messages_info_into(messages, channel_id, params) do
    messages |> get_messages_info(channel_id) |> Enum.into(params)
  end

  defp new_days([h|t], tz, []), do: new_days(t, tz, [Map.put(h, :new_day, true)])
  defp new_days([h|t], tz, [last|_] = acc) do
    dt1 = Timex.shift(h.inserted_at, hours: tz)
    dt2 = Timex.shift(last.inserted_at, hours: tz)
    h = if Timex.day(dt1) == Timex.day(dt2) do
      h
    else
      Map.put(h, :new_day, true)
    end
    new_days t, tz, [h|acc]
  end
  defp new_days([], _, []), do: []
  defp new_days([], _, acc), do: Enum.reverse(acc)

  def last_user_id(channel_id) do
    channel_id
    |> last_message
    |> case do
      nil -> nil
      message -> Map.get(message, :user_id)
    end
  end

  def last_message(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> last
    |> Repo.one
  end

  def first_message(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> first
    |> Repo.one
  end

  def render_message(message) do
    user_id = message.user.id
    user = Repo.one(from u in User, where: u.id == ^user_id)
    "message.html"
    |> UcxChat.MessageView.render(message: message, user: user)
    |> Phoenix.HTML.safe_to_string
  end

  def create_system_message(channel_id, body) do
    bot_id = Helpers.get_bot_id()
    create_message(body, bot_id, channel_id,
      %{
        type: "p",
        system: true,
        sequential: false,
      })
  end

  def create_message(body, user_id, channel_id, params \\ %{}) do
    # Logger.warn "create_msg body: #{inspect body}, params: #{inspect params}"
    sequential? = case last_message(channel_id) do
      nil -> false
      lm ->
        Timex.after?(Timex.shift(lm.inserted_at,
          seconds: Settings.grouping_period_seconds()), Timex.now) and
          user_id == lm.user_id
    end

    message =
      %Message{}
      |> Message.changeset(Map.merge(
        %{
          sequential: sequential?,
          channel_id: channel_id,
          user_id: user_id,
          body: body
        }, params))
      |> Repo.insert!
      |> Repo.preload([:user])
    if params[:type] == "p" do
      Repo.delete(message)
    end
    message
  end

  def stop_typing(socket, user_id, channel_id) do
    TypingAgent.stop_typing(channel_id, user_id)
    update_typing(socket, channel_id)
  end

  def update_typing(%{} = socket, channel_id) do
    typing = TypingAgent.get_typing_names(channel_id)
    Phoenix.Channel.broadcast! socket, "typing:update", %{typing: typing}
  end

  def update_typing(channel_id, room) do
    typing = TypingAgent.get_typing_names(channel_id)
    UcxChat.Endpoint.broadcast(CC.chan_room <> room, "typing:update", %{typing: typing})
  end

  def encode_mentions(body, channel_id) do
    body
    |> encode_user_mentions(channel_id)
    |> encode_channel_mentions
  end

  def encode_channel_mentions({body, acc}) do
    re = ~r/(^|\s|\!|:|,|\?)#([\.a-zA-Z0-9_-]*)/
    body = if (list = Regex.scan(re, body)) != [] do
      Enum.reduce(list, body, fn [_, _, name], body ->
        encode_channel_mention(name, body)
      end)
    else
      body
    end
    {body, acc}
  end

  def encode_channel_mention(name, body) do
    Channel
    |> where([c], c.name == ^name)
    |> Repo.one
    |> do_encode_channel_mention(name, body)
  end

  def do_encode_channel_mention(nil, _, body), do: body
  def do_encode_channel_mention(_channel, name, body) do
    name_link = " <a class='mention-link' data-channel='#{name}'>##{name}</a> "
    String.replace body, ~r/(^|\s|\.|\!|:|,|\?)##{name}[\.\!\?\,\:\s]*/, name_link
  end

  def encode_user_mentions(body, channel_id) do
    re = ~r/(^|\s|\!|:|,|\?)@([\.a-zA-Z0-9_-]*)/
    if (list = Regex.scan(re, body)) != [] do
      Enum.reduce(list, {body, []}, fn [_, _, name], {body, acc} ->
        encode_user_mention(name, body, channel_id, acc)
      end)
    else
      {body, []}
    end
  end

  def encode_user_mention(name, body, channel_id, acc) do
    User
    |> where([c], c.username == ^name)
    |> Repo.one
    |> do_encode_user_mention(name, body, channel_id, acc)
  end

  def do_encode_user_mention(nil, name, body, _, acc) when name in ~w(all here) do
    name_link =
      " <a class='mention-link mention-link-me mention-link-#{name} background-attention-color' >@#{name}</a> "
    body = String.replace body, ~r/(^|\s|\.|\!|:|,|\?)@#{name}[\.\!\?\,\:\s]*/, name_link
    {body, [{nil, name}|acc]}
  end
  def do_encode_user_mention(nil, _, body, _, acc), do: {body, acc}
  def do_encode_user_mention(user, name, body, _channel_id, acc) do
    name_link = " <a class='mention-link' data-username='#{user.username}'>@#{name}</a> "
    body = String.replace body, ~r/(^|\s|\.|\!|:|,|\?)@#{name}[\.\!\?\,\:\s]*/, name_link
    {body, [{user.id, name}|acc]}
  end

  def create_mentions([], _, _), do: :ok
  def create_mentions([mention|mentions], message_id, channel_id) do
    create_mention(mention, message_id, channel_id)
    create_mentions(mentions, message_id, channel_id)
  end

  def create_mention({nil, _}, _, _), do: nil
  def create_mention({mention, name}, message_id, channel_id) do
    {all, nm} = if name in ~w(all here), do: {true, name}, else: {false, nil}
    %Mention{}
    |> Mention.changeset(%{user_id: mention, all: all, name: nm, message_id: message_id, channel_id: channel_id})
    |> Repo.insert!
    |> UserChannel.notify_mention

    subs =
      Subscription
      |> where([s], s.user_id == ^mention and s.channel_id == ^channel_id)
      |> Repo.one
      |> case do
        nil ->
          {:ok, subs} = ChannelService.join_channel(channel_id, mention)
          subs
        subs ->
          subs
      end

    subs
    |> Subscription.changeset(%{unread: subs.unread + 1})
    |> Repo.update!
  end

  def create_and_render(body, user_id, channel_id, opts \\ []) do
    message = create_message(body, user_id, channel_id, Enum.into(opts, %{}))
    {message, render_message(message)}
  end

  # defp notify_mention(_mention) do
  #   # have to figure out if we need to have another socket for this?
  # end

  def render_message_box(channel_id, user_id) do
    user = Helpers.get_user! user_id
    channel = case Helpers.get(Channel, channel_id) do
      nil ->
        Channel
        |> first
        |> Repo.one
      channel ->
        channel
    end
    chatd = ChatDat.new(user, channel)
    MessageView.render("message_box.html", chatd: chatd, mb: MessageView.get_mb(chatd))
    |> Phoenix.HTML.safe_to_string
  end
end
