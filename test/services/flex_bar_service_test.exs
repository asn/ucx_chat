defmodule UcxChat.FlexBarServiceTest do
  use UcxChat.ModelCase

  alias UcxChat.FlexBarService, as: Service
  alias UcxChat.UserAgent, as: Agent
  import UcxChat.TestHelpers


  require Logger
  require IEx
  # def handle_in("close" = event, msg) do
  #   # Logger.warn "FlexBarService.close msg: #{inspect msg}"
  #   UserAgent.close_ftab(msg["user_id"], msg["channel_id"])
  #   {:ok, %{}}
  # end

  @title1 "Stared Messages"
  @title2 "Pinned Messages"
  # @title3 "Members List"
  # @title4 "Mentions"

  setup do
    {:ok, subs: insert_subscription()}
  end

  test "setup", %{subs: subs} do
    assert subs.user.username
  end

  test "close", %{subs: subs} do
    msg = create_msg subs
    open_ftab(msg)
    assert Service.handle_in("close", msg) == {:ok, %{}}
    assert get_ftab(msg) == nil
  end

  test "get_open", %{subs: subs} do
    msg = create_msg subs
    open_ftab msg
    assert Service.handle_in("get_open", msg) == {:ok, %{ftab: %{title: @title1, args: %{}}}}
    close_ftab(msg)
    refute get_ftab(msg)
    assert Service.handle_in("get_open", msg) == {:ok, %{ftab: nil}}
  end

  # def handle_click("Members List" = event, %{"channel_id" => channel_id} = msg)  do

  @title "Members List"
  test "click: #{@title}", %{subs: subs} do
    msg = create_msg(subs) |> Map.put("templ", "users_list.html")

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{"username" => msg["username"]}}
    msg = Map.delete msg, "username"

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end
  # def handle_click("Pinned Messages" = event, %{"user_id" => user_id, "channel_id" => channel_id} = msg) do

  @title "Pinned Messages"
  test "click: #{@title} empty", %{subs: subs} do
    msg = create_msg(subs) |> Map.put("templ", "pinned_messages.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{}}

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end

  @title "Stared Messages"
  test "click: #{@title} empty", %{subs: subs} do
    msg = create_msg(subs) |> Map.put("templ", "stared_messages.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{}}

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end

  @title "Stared Messages"
  test "click: #{@title} not empty", %{subs: subs} do
    message = insert(:message, %{user_id: subs.user_id, channel_id: subs.channel.id})
    insert(:stared_message, %{user_id: subs.user.id, channel_id: subs.channel.id, message_id: message.id})

    msg = create_msg(subs) |> Map.put("templ", "stared_messages.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{}}

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end

  @title "Members List"
  test "click: #{@title} change room", %{subs: subs} do
    msg = create_msg(subs) |> Map.put("templ", "users_list.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}

    msg = Map.put(msg, "templ", "pinned_messages.html")

    {:ok, %{open: true, html: _html}} = Service.handle_click(@title2, msg)
    assert get_ftab(msg) == %{title: @title2, args: %{}}
  end

  # def handle_click("Mentions" = event, %{"user_id" => user_id, "channel_id" => channel_id} = msg) do

  @title "Mentions"
  test "click: #{@title} empty", %{subs: subs} do
    msg = create_msg(subs) |> Map.put("templ", "mentions.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{}}

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end

  @title "Mentions"
  test "click: #{@title} not empty", %{subs: subs} do
    message = insert(:message, %{user_id: subs.user_id, channel_id: subs.channel.id})
    insert(:mention, %{user_id: subs.user.id, channel_id: subs.channel.id, message_id: message.id})
    msg = create_msg(subs) |> Map.put("templ", "mentions.html")
    msg = Map.delete msg, "username"

    {:ok, %{open: true, html: html}} = Service.handle_click(@title, msg)
    assert html
    assert get_ftab(msg) == %{title: @title, args: %{}}

    {:ok, %{close: true}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == nil
    {:ok, %{open: true, html: _html}} = Service.handle_click(@title, msg)
    assert get_ftab(msg) == %{title: @title, args: %{}}
  end

  test "sample", %{subs: _subs} do
  end

  def open_ftab(msg), do: open_ftab(msg, @title1, nil)
  def open_ftab(msg, args) when is_tuple(args), do: open_ftab(msg, @title1, args)
  def open_ftab(msg, title, args) do
    Agent.open_ftab msg["user_id"], msg["channel_id"], title, args
  end

  def get_ftab(msg), do: Agent.get_ftab(msg["user_id"], msg["channel_id"])

  def close_ftab(msg), do: Agent.close_ftab(msg["user_id"], msg["channel_id"])

  def create_msg(subs) do
    %{
      "user_id" => subs.user.id,
      "channel_id" => subs.channel.id,
      "room" => subs.channel.name,
      "username" => subs.user.username,
    }
  end
end
