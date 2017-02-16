import * as utils from './utils'

class Typing {

  constructor(typing) {
    this.typing = typing
    this.timer = undefined
  }

  get is_typing() { return this.typing; }
  set is_typing(val) { this.typing = val; }

  get timer_ref() { this.timer }
  set timer_ref(val) { this.timer = val }

  clear() {
    this.is_typing = false
    clearTimeout(this.timer_ref)
    this.timer_ref = undefined
  }

  start_typing() {
    if (!this.is_typing) {
      this.is_typing = true
      this.timer_ref = setTimeout(this.typing_timer_timeout, 15000, this, ucxchat.channel_id, ucxchat.client_id)
      roomchan.push("typing:start", {channel_id: ucxchat.channel_id,
        client_id: ucxchat.client_id, nickname: ucxchat.nickname, room: ucxchat.room})
    }
  }
  update_typing(typing) {
    console.log('Typing.update_typing', typing)

    if (typing.indexOf(ucxchat.nickname) < 0) {
      this.do_update_typing(false, typing)
    } else {
      utils.remove(typing, ucxchat.nickname)
      this.do_update_typing(true, typing)
    }
  }

  do_update_typing(self_typing, list) {
    console.log('to_update_typing', self_typing, list)
    let len = list.length
    let prepend = ""
    if (len > 1) {
      if (self_typing)
        prepend = " are also typing"
      else
        prepend = " are typing"
    } else if (len == 0) {
      $('form.message-form .users-typing').html('')
      return
    } else {
      if (self_typing)
        prepend = " is also typing"
      else
        prepend = " is typing"
    }

    $('form.message-form .users-typing').html("<strong>" + list.join(", ") + "</strong>" + prepend)
  }

  typing_timer_timeout(this_ref, channel_id, client_id) {
    console.log('typing_timer_timeout', this_ref.is_typing)
    if ($('.message-form-text').val() == '') {
      if (this_ref.is_typing) {
        // assume they cleared the textedit and did not send
        this_ref.is_typing = false
        this_ref.timer_ref = undefined
        roomchan.push("typing:stop", {channel_id: channel_id, client_id: client_id, room: ucxchat.room})
      }
    } else {
      this_ref.timer_ref = setTimeout(this.typing_timer_timeout, 15000, this_ref, channel_id, client_id)
    }
  }
}
export default Typing