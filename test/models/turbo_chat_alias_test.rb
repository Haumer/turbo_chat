require_relative "../test_helper"

class TurboChatAliasTest < ActiveSupport::TestCase
  test "TurboChat delegates to ChatGem for backwards compatibility" do
    assert_equal ChatGem.configuration, TurboChat.configuration
    assert_equal ChatGem::VERSION, TurboChat::VERSION
    assert_equal ChatGem::Engine, TurboChat::Engine
    assert_equal ChatGem::Chat, TurboChat::Chat
  end
end
