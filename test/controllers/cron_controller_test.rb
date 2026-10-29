require "test_helper"

class CronControllerTest < ActionDispatch::IntegrationTest
  test "rejects requests without the cron secret" do
    with_env_overrides CRON_SECRET: "secret" do
      ImportMarketDataJob.expects(:perform_later).never

      get cron_daily_url, headers: { "Authorization" => "Bearer wrong" }

      assert_response :unauthorized
    end
  end

  test "enqueues scheduled jobs with a valid cron secret" do
    with_env_overrides CRON_SECRET: "secret" do
      ImportMarketDataJob.expects(:perform_later).with(mode: "full", clear_cache: false).once
      SyncCleanerJob.expects(:perform_later).once
      SecurityHealthCheckJob.expects(:perform_later).once

      get cron_daily_url, headers: { "Authorization" => "Bearer secret" }

      assert_response :ok
    end
  end
end
