require_relative "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["CI"].to_s == "true" || ENV["CHAT_GEM_SYSTEM_TEST_CHROME"] == "1"
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]
  else
    driven_by :selenium, using: :safari, screen_size: [1400, 900]
  end

  setup do
    skip_unless_system_driver_available!
  end

  private

  def skip_unless_system_driver_available!
    if self.class.chrome_mode?
      skip_unless_chrome_webdriver_available!
    else
      skip_unless_safari_webdriver_available!
    end
  end

  def skip_unless_chrome_webdriver_available!
    return if self.class.chrome_webdriver_available?

    message = "Chrome WebDriver unavailable: #{self.class.chrome_webdriver_error}"
    raise Minitest::Assertion, message if ENV["CI"].to_s == "true"

    skip message
  end

  def skip_unless_safari_webdriver_available!
    return if self.class.safari_webdriver_available?

    skip "Safari WebDriver unavailable: #{self.class.safari_webdriver_error}"
  end

  class << self
    def chrome_mode?
      ENV["CI"].to_s == "true" || ENV["CHAT_GEM_SYSTEM_TEST_CHROME"] == "1"
    end

    def chrome_webdriver_available?
      check_chrome_webdriver_availability! unless defined?(@chrome_webdriver_available)

      @chrome_webdriver_available
    end

    def chrome_webdriver_error
      check_chrome_webdriver_availability! unless defined?(@chrome_webdriver_available)

      @chrome_webdriver_error
    end

    def safari_webdriver_available?
      check_safari_webdriver_availability! unless defined?(@safari_webdriver_available)

      @safari_webdriver_available
    end

    def safari_webdriver_error
      check_safari_webdriver_availability! unless defined?(@safari_webdriver_available)

      @safari_webdriver_error
    end

    private

    def check_chrome_webdriver_availability!
      driver = nil
      begin
        options = Selenium::WebDriver::Chrome::Options.new
        options.add_argument("--headless=new")
        options.add_argument("--disable-gpu")
        options.add_argument("--no-sandbox")
        driver = Selenium::WebDriver.for(:chrome, options: options)
        @chrome_webdriver_available = true
        @chrome_webdriver_error = nil
      rescue StandardError => error
        @chrome_webdriver_available = false
        @chrome_webdriver_error = "#{error.class}: #{error.message}"
      ensure
        driver&.quit
      end
    end

    def check_safari_webdriver_availability!
      driver = nil
      begin
        driver = Selenium::WebDriver.for(:safari)
        @safari_webdriver_available = true
        @safari_webdriver_error = nil
      rescue StandardError => error
        @safari_webdriver_available = false
        @safari_webdriver_error = "#{error.class}: #{error.message}"
      ensure
        driver&.quit
      end
    end
  end
end
